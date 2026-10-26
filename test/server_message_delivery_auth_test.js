'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'authenticated delivery test',
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

test('actual recipient can acknowledge delivery', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  assert.equal(tx.markDelivered(message, 'bob'), true);
  assert.equal(tx.get(message).status, 'delivered');
});

test('sender cannot acknowledge recipient delivery', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  assert.equal(tx.markDelivered(message, 'alice'), false);
  assert.equal(tx.get(message).status, 'pending');
});

test('unrelated user cannot acknowledge delivery', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  assert.equal(tx.markDelivered(message, 'charlie'), false);
  assert.equal(tx.get(message).status, 'pending');
});

test('missing authenticated recipient is rejected', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  assert.equal(tx.markDelivered(message), false);
  assert.equal(tx.markDelivered(message, null), false);
  assert.equal(tx.markDelivered(message, ''), false);
  assert.equal(tx.get(message).status, 'pending');
});

test('claiming a different recipient is rejected', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);

  const forged = { ...message, to: 'charlie' };

  assert.equal(tx.markDelivered(forged, 'charlie'), false);
  assert.equal(tx.get(message).status, 'pending');
});

test('unauthorized acknowledgement cannot erase pending payload', () => {
  const tx = createMessageTransaction({ store: createStore() });

  tx.accept(message);
  tx.markDelivered(message, 'charlie');

  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(tx.pendingFor('bob')[0].text, message.text);
});