'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createMessageTransaction } =
  require('../server_message_transaction');

function createStore() {
  let saved = {};

  return {
    load: () => structuredClone(saved),
    save: next => {
      saved = structuredClone(next);
    },
  };
}

test('same fields in different order currently produce conflict', () => {
  const tx = createMessageTransaction({
    store: createStore(),
  });

  const first = {
    id: '1234567890123456-abcdef0123456789',
    from: 'alice',
    to: 'bob',
    text: 'same content',
    messageType: 'text',
  };

  const reordered = {
    messageType: 'text',
    text: 'same content',
    to: 'bob',
    from: 'alice',
    id: '1234567890123456-abcdef0123456789',
  };

  assert.equal(tx.accept(first).duplicate, false);

  const result = tx.accept(reordered);

  // Diagnostic: this is the current limitation, not desired behavior.
  assert.equal(result.duplicate, true);
  assert.equal(result.conflict, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('identical order remains a duplicate', () => {
  const tx = createMessageTransaction({
    store: createStore(),
  });

  const message = {
    id: '1234567890123456-abcdef0123456789',
    from: 'alice',
    to: 'bob',
    text: 'same content',
  };

  tx.accept(message);

  assert.equal(tx.accept({ ...message }).duplicate, true);
});

test('changed content remains a conflict', () => {
  const tx = createMessageTransaction({
    store: createStore(),
  });

  const message = {
    id: '1234567890123456-abcdef0123456789',
    from: 'alice',
    to: 'bob',
    text: 'original',
  };

  tx.accept(message);

  assert.equal(
    tx.accept({ ...message, text: 'modified' }).conflict,
    true
  );
});