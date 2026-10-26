'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createMessageTransaction } =
  require('../server_message_transaction');

const msg = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'version test',
};

const key = JSON.stringify([msg.from, msg.to, msg.id]);

function backend(initial = {}) {
  let saved = structuredClone(initial);

  return {
    load: () => structuredClone(saved),
    save: next => { saved = structuredClone(next); },
  };
}

test('new acceptance stores fingerprint version 2', () => {
  const tx = createMessageTransaction({ store: backend() });
  tx.accept(msg);

  assert.equal(tx.get(msg).payloadHashVersion, 2);
  assert.match(tx.get(msg).payloadHash, /^[a-f0-9]{64}$/);
});

test('version 2 survives delivery and restart', () => {
  const store = backend();
  const first = createMessageTransaction({ store });

  first.accept(msg);
  first.markDelivered(msg, 'bob');

  const restarted = createMessageTransaction({ store });

  assert.equal(restarted.get(msg).payloadHashVersion, 2);
  assert.equal(restarted.accept(msg).duplicate, true);
  assert.equal(
    restarted.accept({ ...msg, text: 'changed' }).conflict,
    true
  );
});

test('legacy unversioned record with payload remains readable', () => {
  const hash = crypto.createHash('sha256')
    .update(JSON.stringify(msg))
    .digest('hex');

  const tx = createMessageTransaction({
    store: backend({
      [key]: {
        ...msg,
        status: 'pending',
        payload: msg,
        payloadHash: hash,
      },
    }),
  });

  assert.equal(tx.accept(msg).duplicate, true);
});

test('unsupported fingerprint version fails closed', () => {
  const tx = createMessageTransaction({
    store: backend({
      [key]: {
        ...msg,
        status: 'delivered',
        payload: null,
        payloadHashVersion: 999,
        payloadHash: '0'.repeat(64),
      },
    }),
  });

  assert.equal(tx.accept(msg).conflict, true);
});