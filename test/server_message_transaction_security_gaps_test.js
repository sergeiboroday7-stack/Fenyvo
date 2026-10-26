'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'original message',
};

function createStore() {
  let saved = {};

  return {
    load: () => structuredClone(saved),
    save: next => {
      saved = structuredClone(next);
    },
  };
}

test('same ID with changed content currently returns duplicate', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  const retry = tx.accept({
    ...message,
    text: 'different content',
  });

  assert.equal(retry.duplicate, false);
  assert.equal(retry.conflict, true);
  assert.equal(retry.record, null);
  assert.equal(tx.get(message).payload.text, 'original message');
});

test('transaction module does not authenticate delivery caller', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  // No authenticated user is supplied to markDelivered().
  // This test documents the limitation; it is not an exploit test
  // against the actual WebSocket server.
  assert.equal(tx.markDelivered(message, 'bob'), true);
  assert.equal(tx.get(message).status, 'delivered');
});

test('duplicate acceptance exposes original record metadata', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  const retry = tx.accept(message);

  assert.equal(retry.duplicate, true);
  assert.equal(retry.record.from, 'alice');
  assert.equal(retry.record.to, 'bob');
  assert.equal(retry.record.status, 'pending');
});

test('delivered record retains identity but not payload', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);
  tx.markDelivered(message, 'bob');

  const record = tx.get(message);

  assert.equal(record.status, 'delivered');
  assert.equal(record.payload, null);
  assert.equal(record.id, message.id);
});

test('recipient queue currently has no enforced page size', () => {
  const tx = createMessageTransaction({ store: createStore() });

  for (let i = 0; i < 20; i++) {
    tx.accept({
      ...message,
      id: `test-message-${i}`,
    });
  }

  assert.equal(tx.pendingFor('bob').length, 20);
});