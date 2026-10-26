'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createRecoveryTransactionLock } = require('../server_recovery_transaction');

test('blocks concurrent operations for the same account', async () => {
  const lock = createRecoveryTransactionLock();
  let release;
  const wait = new Promise(resolve => { release = resolve; });
  const first = lock.run('alice', async () => { await wait; return 'done'; });
  await assert.rejects(lock.run('alice', async () => 'second'), /already in progress/);
  release();
  assert.equal(await first, 'done');
});

test('releases account lock after failure', async () => {
  const lock = createRecoveryTransactionLock();
  await assert.rejects(lock.run('alice', async () => { throw new Error('simulated failure'); }), /simulated failure/);
  assert.equal(await lock.run('alice', async () => 'retry allowed'), 'retry allowed');
});

test('allows independent accounts concurrently', async () => {
  const lock = createRecoveryTransactionLock();
  let release;
  const wait = new Promise(resolve => { release = resolve; });
  const first = lock.run('alice', async () => { await wait; return 'alice done'; });
  assert.equal(await lock.run('bob', async () => 'bob done'), 'bob done');
  release();
  assert.equal(await first, 'alice done');
});
