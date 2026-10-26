'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'test message',
};

function createTestBackend() {
  let disk = {};
  let failSave = false;

  return {
    load() {
      return structuredClone(disk);
    },
    save(next) {
      if (failSave) throw new Error('simulated disk failure');
      disk = structuredClone(next);
    },
    setFailure(value) {
      failSave = value;
    },
  };
}

test('failed acceptance does not produce server acknowledgement state', () => {
  const store = createTestBackend();
  const tx = createMessageTransaction({ store });

  store.setFailure(true);

  assert.throws(() => tx.accept(message), /disk failure/);
  assert.equal(tx.get(message), null);
  assert.equal(tx.pendingFor('bob').length, 0);

  store.setFailure(false);

  assert.equal(tx.accept(message).duplicate, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('restart preserves accepted message and prevents duplicate acceptance', () => {
  const store = createTestBackend();

  const first = createMessageTransaction({ store });
  first.accept(message);

  const restarted = createMessageTransaction({ store });

  assert.equal(restarted.pendingFor('bob').length, 1);
  assert.equal(restarted.accept(message).duplicate, true);
});

test('failed delivery-state write keeps message pending', () => {
  const store = createTestBackend();
  const tx = createMessageTransaction({ store });

  tx.accept(message);

  store.setFailure(true);

  assert.throws(() => tx.markDelivered(message, 'bob'), /disk failure/);

  assert.equal(tx.get(message).status, 'pending');
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('successful delivery clears pending payload but remembers ID', () => {
  const store = createTestBackend();
  const tx = createMessageTransaction({ store });

  tx.accept(message);
  tx.markDelivered(message, 'bob');

  const restarted = createMessageTransaction({ store });

  assert.equal(restarted.pendingFor('bob').length, 0);
  assert.equal(restarted.get(message).status, 'delivered');
  assert.equal(restarted.accept(message).duplicate, true);
});

test('different messages remain independent', () => {
  const store = createTestBackend();
  const tx = createMessageTransaction({ store });

  tx.accept(message);
  tx.accept({ ...message, id: message.id + '-2' });

  assert.equal(tx.pendingFor('bob').length, 2);
});