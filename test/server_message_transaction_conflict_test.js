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
  text: 'original',
};

function withFile(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-conflict-'));
  const filePath = path.join(dir, 'messages.json');

  try {
    fn(filePath);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('identical retry remains a duplicate', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });
    tx.accept(message);

    const result = tx.accept({ ...message });

    assert.equal(result.duplicate, true);
    assert.equal(result.conflict, false);
  });
});

test('changed content with same ID is a conflict', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });
    tx.accept(message);

    const result = tx.accept({ ...message, text: 'modified' });

    assert.equal(result.conflict, true);
    assert.equal(result.record, null);
    assert.equal(tx.pendingFor('bob').length, 1);
    assert.equal(tx.pendingFor('bob')[0].text, 'original');
  });
});

test('conflict survives restart', () => {
  withFile(filePath => {
    createMessageTransaction({ filePath }).accept(message);

    const tx = createMessageTransaction({ filePath });

    assert.equal(
      tx.accept({ ...message, text: 'modified' }).conflict,
      true
    );
  });
});

test('conflict survives delivery cleanup', () => {
  withFile(filePath => {
    const first = createMessageTransaction({ filePath });

    first.accept(message);
    first.markDelivered(message, 'bob');

    const restarted = createMessageTransaction({ filePath });

    assert.equal(restarted.accept(message).duplicate, true);
    assert.equal(
      restarted.accept({ ...message, text: 'modified' }).conflict,
      true
    );
    assert.equal(restarted.pendingFor('bob').length, 0);
  });
});

test('different ID remains acceptable', () => {
  withFile(filePath => {
    const tx = createMessageTransaction({ filePath });

    assert.equal(tx.accept(message).duplicate, false);
    assert.equal(
      tx.accept({ ...message, id: 'another-message-id' }).duplicate,
      false
    );
  });
});