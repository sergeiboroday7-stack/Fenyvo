'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'legacy test',
};

const key = JSON.stringify([message.from, message.to, message.id]);

function legacyHash(value) {
  return crypto.createHash('sha256')
    .update(JSON.stringify(value))
    .digest('hex');
}

function createStore(initial) {
  let disk = structuredClone(initial);

  return {
    load: () => structuredClone(disk),
    save: next => { disk = structuredClone(next); },
  };
}

function legacyRecord(payload) {
  return {
    id: message.id,
    from: message.from,
    to: message.to,
    status: payload ? 'pending' : 'delivered',
    payload: payload ? structuredClone(payload) : null,
    payloadHash: legacyHash(message),
    acceptedAt: '2026-10-24T00:00:00.000Z',
  };
}

test('old fingerprint with payload accepts identical retry', () => {
  const tx = createMessageTransaction({
    store: createStore({ [key]: legacyRecord(message) }),
  });

  assert.equal(tx.accept(message).duplicate, true);
});

test('old fingerprint with payload accepts reordered retry', () => {
  const tx = createMessageTransaction({
    store: createStore({ [key]: legacyRecord(message) }),
  });

  const reordered = {
    text: message.text,
    to: message.to,
    from: message.from,
    id: message.id,
  };

  assert.equal(tx.accept(reordered).duplicate, true);
});

test('old fingerprint without payload fails closed', () => {
  const tx = createMessageTransaction({
    store: createStore({ [key]: legacyRecord(null) }),
  });

  const result = tx.accept(message);

  // Diagnostic: no trustworthy conversion is possible
  // without the original payload or a versioned fingerprint.
  assert.equal(result.conflict, true);
  assert.equal(result.record, null);
});

test('new record survives delivery cleanup and restart', () => {
  const store = createStore({});

  const first = createMessageTransaction({ store });
  first.accept(message);
  first.markDelivered(message, 'bob');

  const restarted = createMessageTransaction({ store });

  assert.equal(restarted.accept(message).duplicate, true);
  assert.equal(
    restarted.accept({ ...message, text: 'changed' }).conflict,
    true
  );
});