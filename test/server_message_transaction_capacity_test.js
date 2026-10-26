'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

function backend() {
  let data = {};

  return {
    load: () => structuredClone(data),
    save: next => { data = structuredClone(next); },
    snapshot: () => structuredClone(data),
  };
}

const msg = (id, text = 'test') => ({
  id,
  from: 'alice',
  to: 'bob',
  text,
});

test('small message fits configured storage capacity', () => {
  const store = backend();

  const tx = createMessageTransaction({
    store,
    maxStorageBytes: 2048,
  });

  assert.equal(tx.accept(msg('capacity-1')).duplicate, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('capacity overflow does not erase pending messages', () => {
  const store = backend();

  const tx = createMessageTransaction({
    store,
    maxStorageBytes: 1024,
  });

  tx.accept(msg('capacity-2'));

  const before = store.snapshot();

  assert.throws(
    () => tx.accept(msg('capacity-3', 'x'.repeat(1800))),
    /capacity exceeded/
  );

  assert.deepEqual(store.snapshot(), before);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('delivery still works at storage capacity', () => {
  const store = backend();

  const tx = createMessageTransaction({
    store,
    maxStorageBytes: 1024,
  });

  const item = msg('capacity-4', 'x'.repeat(300));

  tx.accept(item);
  assert.equal(tx.markDelivered(item, 'bob'), true);

  assert.equal(tx.pendingFor('bob').length, 0);
  assert.equal(tx.get(item).payload, null);
});

test('invalid overall capacity is rejected', () => {
  assert.throws(
    () => createMessageTransaction({
      store: backend(),
      maxStorageBytes: 0,
    }),
    RangeError
  );
});

test('capacity rejection survives restart without duplicate loss', () => {
  const store = backend();

  const first = createMessageTransaction({
    store,
    maxStorageBytes: 1024,
  });

  const item = msg('capacity-5');
  first.accept(item);

  assert.throws(
    () => first.accept(msg('capacity-6', 'x'.repeat(1800))),
    /capacity exceeded/
  );

  const restarted = createMessageTransaction({
    store,
    maxStorageBytes: 1024,
  });

  assert.equal(restarted.accept(item).duplicate, true);
  assert.equal(restarted.pendingFor('bob').length, 1);
});