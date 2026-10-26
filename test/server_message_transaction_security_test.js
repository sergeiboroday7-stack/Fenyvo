'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'security test',
};

function createStore() {
  let disk = {};

  return {
    load: () => structuredClone(disk),
    save: next => {
      disk = structuredClone(next);
    },
  };
}

test('unknown ID cannot be marked delivered', () => {
  const tx = createMessageTransaction({ store: createStore() });

  assert.equal(tx.markDelivered(message, 'bob'), false);
});

test('different sender cannot alter another message record', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  assert.equal(
    tx.markDelivered({ ...message, from: 'charlie' }, 'bob'),
    false
  );

  assert.equal(tx.get(message).status, 'pending');
});

test('different recipient cannot alter another message record', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  assert.equal(
    tx.markDelivered({ ...message, to: 'charlie' }, 'bob'),
    false
  );

  assert.equal(tx.get(message).status, 'pending');
});

test('mutating returned record cannot change stored record', () => {
  const tx = createMessageTransaction({ store: createStore() });

  const result = tx.accept(message);
  result.record.status = 'delivered';
  result.record.payload.text = 'modified';

  const stored = tx.get(message);

  assert.equal(stored.status, 'pending');
  assert.equal(stored.payload.text, 'security test');
});

test('retry with same ID cannot replace original payload', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  const retry = tx.accept({
    ...message,
    text: 'different text',
  });

  assert.equal(retry.duplicate, false);
  assert.equal(retry.conflict, true);
  assert.equal(retry.record, null);
  assert.equal(tx.get(message).payload.text, 'security test');
});

test('pending messages are returned only for requested recipient', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);
  tx.accept({
    ...message,
    id: message.id + '-2',
    to: 'charlie',
  });

  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(tx.pendingFor('charlie').length, 1);
  assert.equal(tx.pendingFor('dave').length, 0);
});