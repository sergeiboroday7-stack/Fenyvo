'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createMessageAcceptanceStore } =
  require('../server_message_acceptance_store');

const message = {
  from: 'alice',
  to: 'bob',
  id: '1234567890123456-abcdef0123456789',
};

function withTempFile(run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-accept-'));
  const filePath = path.join(dir, 'acceptance.json');

  try {
    run(filePath);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('first message accepted and stored', () => {
  withTempFile(filePath => {
    const storage = createMessageAcceptanceStore({ filePath });

    assert.equal(storage.accept(message).accepted, true);
    assert.equal(storage.get(message).status, 'accepted');
  });
});

test('retry returns prior acceptance without second insertion', () => {
  withTempFile(filePath => {
    const storage = createMessageAcceptanceStore({ filePath });

    storage.accept(message);
    const retry = storage.accept(message);

    assert.equal(retry.duplicate, true);
    assert.equal(retry.record.id, message.id);
  });
});

test('accepted record survives restart', () => {
  withTempFile(filePath => {
    createMessageAcceptanceStore({ filePath }).accept(message);

    const restarted = createMessageAcceptanceStore({ filePath });

    assert.equal(restarted.accept(message).duplicate, true);
  });
});

test('delivery state survives restart', () => {
  withTempFile(filePath => {
    const first = createMessageAcceptanceStore({ filePath });

    first.accept(message);
    assert.equal(first.markDelivered(message), true);

    const restarted = createMessageAcceptanceStore({ filePath });
    assert.equal(restarted.get(message).status, 'delivered');
  });
});

test('failed persistence does not register acceptance', () => {
  let fail = true;
  let saved = {};

  const store = {
    load: () => saved,
    save: next => {
      if (fail) throw new Error('disk failure');
      saved = structuredClone(next);
    },
  };

  const storage = createMessageAcceptanceStore({ store });

  assert.throws(() => storage.accept(message), /disk failure/);
  assert.equal(storage.get(message), null);

  fail = false;

  assert.equal(storage.accept(message).accepted, true);
});

test('same ID from different senders is distinct', () => {
  withTempFile(filePath => {
    const storage = createMessageAcceptanceStore({ filePath });

    assert.equal(storage.accept(message).accepted, true);
    assert.equal(
      storage.accept({ ...message, from: 'charlie' }).accepted,
      true
    );
  });
});