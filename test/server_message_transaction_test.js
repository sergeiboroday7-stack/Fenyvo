'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'test message',
};

function withFile(run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-tx-'));
  const filePath = path.join(dir, 'transaction.json');

  try {
    run(filePath);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('message and ID accepted together', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });

    assert.equal(tx.accept(message).duplicate, false);
    assert.equal(tx.pendingFor('bob').length, 1);
    assert.equal(tx.pendingFor('bob')[0].id, message.id);
  });
});

test('same ID never creates a second pending entry', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });

    tx.accept(message);
    assert.equal(tx.accept(message).duplicate, true);
    assert.equal(tx.pendingFor('bob').length, 1);
  });
});

test('message survives restart without duplicate', () => {
  withFile(filePath => {
    createMessageTransaction({ filePath }).accept(message);

    const restarted = createMessageTransaction({ filePath });

    assert.equal(restarted.pendingFor('bob').length, 1);
    assert.equal(restarted.accept(message).duplicate, true);
  });
});

test('delivery acknowledgement clears pending payload', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });

    tx.accept(message);
    assert.equal(tx.markDelivered(message, 'bob'), true);
    assert.equal(tx.pendingFor('bob').length, 0);
    assert.equal(tx.accept(message).duplicate, true);
  });
});

test('failed disk write does not accept message', () => {
  let fail = true;
  let saved = {};

  const store = {
    load: () => structuredClone(saved),
    save: next => {
      if (fail) throw new Error('disk unavailable');
      saved = structuredClone(next);
    },
  };

  const tx = createMessageTransaction({ store });

  assert.throws(() => tx.accept(message), /disk unavailable/);
  assert.equal(tx.get(message), null);

  fail = false;
  assert.equal(tx.accept(message).duplicate, false);
});

test('encrypted payload remains opaque', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });

    const encrypted = {
      ...message,
      text: undefined,
      e2ee: true,
      ciphertext: 'opaque-base64-test',
    };

    tx.accept(encrypted);

    assert.equal(tx.pendingFor('bob')[0].ciphertext, encrypted.ciphertext);
    assert.equal(tx.pendingFor('bob')[0].e2ee, true);
  });
});