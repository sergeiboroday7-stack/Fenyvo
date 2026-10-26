'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

function backend() {
  let saved = {};

  return {
    load: () => structuredClone(saved),
    save: next => { saved = structuredClone(next); },
    snapshot: () => structuredClone(saved),
  };
}

function message(id) {
  return {
    id,
    from: 'alice',
    to: 'bob',
    text: 'cleanup test',
  };
}

test('pending message is retained until delivery acknowledgement', () => {
  const store = backend();
  const tx = createMessageTransaction({ store });

  const item = message('pending-message-123');
  tx.accept(item);

  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(Object.keys(store.snapshot()).length, 1);
});

test('delivered message retains ID without payload', () => {
  const store = backend();
  const tx = createMessageTransaction({ store });

  const item = message('delivered-message-123');

  tx.accept(item);
  tx.markDelivered(item, 'bob');

  const record = tx.get(item);

  assert.equal(record.status, 'delivered');
  assert.equal(record.payload, null);
  assert.equal(record.payloadHashVersion, 2);
});

test('delivered record survives restart for duplicate protection', () => {
  const store = backend();

  const item = message('restarted-message-123');
  const first = createMessageTransaction({ store });

  first.accept(item);
  first.markDelivered(item, 'bob');

  const restarted = createMessageTransaction({ store });

  assert.equal(restarted.accept(item).duplicate, true);
  assert.equal(restarted.pendingFor('bob').length, 0);
});

test('pending and delivered records can be distinguished', () => {
  const store = backend();
  const tx = createMessageTransaction({ store });

  const pending = message('pending-record-123');
  const delivered = message('delivered-record-123');

  tx.accept(pending);
  tx.accept(delivered);
  tx.markDelivered(delivered, 'bob');

  const records = Object.values(store.snapshot());

  assert.equal(
    records.filter(record => record.status === 'pending').length,
    1
  );

  assert.equal(
    records.filter(record => record.status === 'delivered').length,
    1
  );
});

test('diagnostic: delivered records are not yet automatically expired', () => {
  const store = backend();
  const tx = createMessageTransaction({ store });

  for (let i = 0; i < 20; i++) {
    const item = message(`old-delivered-${i}`);
    tx.accept(item);
    tx.markDelivered(item, 'bob');
  }

  assert.equal(Object.keys(store.snapshot()).length, 20);
  assert.equal(tx.pendingFor('bob').length, 0);
});