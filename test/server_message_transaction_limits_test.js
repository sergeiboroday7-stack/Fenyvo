'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createMessageTransaction } =
  require('../server_message_transaction');

function backend() {
  let saved = {};

  return {
    load: () => structuredClone(saved),
    save: next => {
      saved = structuredClone(next);
    },
    snapshot: () => structuredClone(saved),
  };
}

function message(id, text = 'test') {
  return {
    id,
    from: 'alice',
    to: 'bob',
    text,
  };
}

test('oversized message is rejected without entering queue', () => {
  const tx = createMessageTransaction({ store: backend() });

  const largeText = 'x'.repeat(1024 * 1024);
  const item = message('large-message-123', largeText);

  assert.throws(
    () => tx.accept(item),
    /exceeds size limit/
  );

  assert.equal(tx.pendingFor('bob').length, 0);
});

test('message under size limit is accepted', () => {
  const tx = createMessageTransaction({
    store: backend(),
    maxPayloadBytes: 2048,
  });

  const result = tx.accept(
    message('small-message-123', 'short text')
  );

  assert.equal(result.duplicate, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('UTF-8 bytes count toward payload limit', () => {
  const item = message('unicode-message-123', 'Привет 🌍');
  const serializedBytes = Buffer.byteLength(
    JSON.stringify(item),
    'utf8'
  );

  const tx = createMessageTransaction({
    store: backend(),
    maxPayloadBytes: serializedBytes - 1,
  });

  assert.throws(
    () => tx.accept(item),
    /exceeds size limit/
  );
});

test('invalid payload size configuration is rejected', () => {
  assert.throws(
    () => createMessageTransaction({
      store: backend(),
      maxPayloadBytes: 0,
    }),
    RangeError
  );
});

test('diagnostic: pending queue has no fixed count limit', () => {
  const tx = createMessageTransaction({ store: backend() });

  for (let i = 0; i < 100; i++) {
    tx.accept(message(`limit-test-${i}`));
  }

  assert.equal(tx.pendingFor('bob').length, 100);
});

test('diagnostic: delivered messages retain metadata records', () => {
  const store = backend();
  const tx = createMessageTransaction({ store });

  for (let i = 0; i < 30; i++) {
    const item = message(`delivered-test-${i}`);
    tx.accept(item);
    tx.markDelivered(item, 'bob');
  }

  assert.equal(tx.pendingFor('bob').length, 0);
  assert.equal(Object.keys(store.snapshot()).length, 30);
});

test('pending message payload is cleared after delivery', () => {
  const tx = createMessageTransaction({ store: backend() });
  const item = message('cleanup-test-123', 'temporary content');

  tx.accept(item);
  tx.markDelivered(item, 'bob');

  const record = tx.get(item);

  assert.equal(record.status, 'delivered');
  assert.equal(record.payload, null);
  assert.equal(record.payloadHashVersion, 2);
});

test('different recipients have separate pending lists', () => {
  const tx = createMessageTransaction({ store: backend() });

  tx.accept(message('recipient-bob-123'));
  tx.accept({
    ...message('recipient-charlie-123'),
    to: 'charlie',
  });

  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(tx.pendingFor('charlie').length, 1);
});