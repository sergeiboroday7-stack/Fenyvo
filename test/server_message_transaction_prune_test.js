'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createMessageTransaction } =
  require('../server_message_transaction');

const msg = id => ({
  id,
  from: 'alice',
  to: 'bob',
  text: 'retention test',
});

function backend() {
  let disk = {};
  let failure = false;

  return {
    load: () => structuredClone(disk),
    save(next) {
      if (failure) throw new Error('disk failure');
      disk = structuredClone(next);
    },
    snapshot: () => structuredClone(disk),
    setFailure: value => { failure = value; },
  };
}

test('delivered record retained before deadline', () => {
  let clock = 1000;
  const store = backend();
  const tx = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 5000,
  });

  tx.accept(msg('retention-1'));
  tx.markDelivered(msg('retention-1'), 'bob');

  clock = 5999;
  assert.equal(tx.pruneDelivered(), 0);
  assert.equal(tx.get(msg('retention-1')).status, 'delivered');
});

test('delivered record pruned after deadline', () => {
  let clock = 1000;
  const store = backend();
  const tx = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 5000,
  });

  tx.accept(msg('retention-2'));
  tx.markDelivered(msg('retention-2'), 'bob');

  clock = 6000;
  assert.equal(tx.pruneDelivered(), 1);
  assert.equal(tx.get(msg('retention-2')), null);
});

test('pending records are never removed by retention pruning', () => {
  let clock = 1000;
  const store = backend();
  const tx = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 100,
  });

  tx.accept(msg('pending-1'));
  tx.accept(msg('delivered-1'));
  tx.markDelivered(msg('delivered-1'), 'bob');

  clock = 5000;
  assert.equal(tx.pruneDelivered(), 1);
  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(tx.pendingFor('bob')[0].id, 'pending-1');
});

test('pruning survives restart', () => {
  let clock = 1000;
  const store = backend();

  const first = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 100,
  });

  first.accept(msg('restart-prune-1'));
  first.markDelivered(msg('restart-prune-1'), 'bob');

  clock = 2000;

  const restarted = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 100,
  });

  assert.equal(restarted.pruneDelivered(), 1);
  assert.equal(restarted.get(msg('restart-prune-1')), null);
});

test('disk error preserves delivered record', () => {
  let clock = 1000;
  const store = backend();

  const tx = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 100,
  });

  tx.accept(msg('disk-failure-1'));
  tx.markDelivered(msg('disk-failure-1'), 'bob');

  clock = 2000;
  store.setFailure(true);

  assert.throws(() => tx.pruneDelivered(), /disk failure/);
  assert.equal(tx.get(msg('disk-failure-1')).status, 'delivered');

  store.setFailure(false);
  assert.equal(tx.pruneDelivered(), 1);
});

test('legacy delivered record without timestamp is preserved', () => {
  let clock = 1000;
  const store = backend();
  const tx = createMessageTransaction({
    store,
    now: () => clock,
    deliveredRetentionMs: 100,
  });

  tx.accept(msg('legacy-delivered-1'));
  tx.markDelivered(msg('legacy-delivered-1'), 'bob');

  const snapshot = store.snapshot();
  const key = JSON.stringify(['alice', 'bob', 'legacy-delivered-1']);
  delete snapshot[key].deliveredAtMs;

  const legacyStore = {
    load: () => structuredClone(snapshot),
    save: () => {},
  };

  const legacy = createMessageTransaction({
    store: legacyStore,
    now: () => 999999,
    deliveredRetentionMs: 100,
  });

  assert.equal(legacy.pruneDelivered(), 0);
  assert.equal(legacy.get(msg('legacy-delivered-1')).status, 'delivered');
});

test('invalid retention configuration is rejected', () => {
  assert.throws(
    () => createMessageTransaction({
      store: backend(),
      deliveredRetentionMs: 0,
    }),
    RangeError
  );
});