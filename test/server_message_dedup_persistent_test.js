'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createPersistentMessageDedup } =
  require('../server_message_dedup_persistent');

const msg = {
  from: 'alice',
  to: 'bob',
  id: '1234567890123456-abcdef0123456789',
};

function withTempFile(run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-persistent-'));
  const filePath = path.join(dir, 'message_dedup.json');

  try {
    run(filePath);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('first delivery accepted, repeat rejected', () => {
  withTempFile(filePath => {
    const dedup = createPersistentMessageDedup({ filePath });
    assert.equal(dedup.mark(msg), true);
    assert.equal(dedup.mark(msg), false);
  });
});

test('dedup survives restart', () => {
  withTempFile(filePath => {
    const first = createPersistentMessageDedup({ filePath });
    first.mark(msg);

    const restarted = createPersistentMessageDedup({ filePath });
    assert.equal(restarted.has(msg), true);
    assert.equal(restarted.mark(msg), false);
  });
});

test('different IDs are accepted', () => {
  withTempFile(filePath => {
    const dedup = createPersistentMessageDedup({ filePath });
    assert.equal(dedup.mark(msg), true);
    assert.equal(dedup.mark({ ...msg, id: msg.id + '-2' }), true);
  });
});

test('expiry permits processing after TTL', () => {
  withTempFile(filePath => {
    let clock = 1000;
    const dedup = createPersistentMessageDedup({
      filePath,
      ttlMs: 5000,
      now: () => clock,
    });

    assert.equal(dedup.mark(msg), true);
    clock = 6000;
    assert.equal(dedup.has(msg), false);
    assert.equal(dedup.mark(msg), true);
  });
});

test('failed persistence does not mark the ID', () => {
  const store = {
    load: () => ({}),
    save: () => {
      throw new Error('simulated disk failure');
    },
  };

  const dedup = createPersistentMessageDedup({ store });

  assert.throws(() => dedup.mark(msg), /disk failure/);
  assert.equal(dedup.has(msg), false);
});

test('corrupted storage prevents initialization', () => {
  const store = {
    load: () => ({ bad: 'not-an-expiry' }),
    save: () => {},
  };

  assert.throws(
    () => createPersistentMessageDedup({ store }),
    /Invalid stored expiration/
  );
});

test('expired records removed during subsequent successful save', () => {
  withTempFile(filePath => {
    let clock = 1000;
    const dedup = createPersistentMessageDedup({
      filePath,
      ttlMs: 100,
      now: () => clock,
    });

    dedup.mark(msg);
    clock = 1200;
    dedup.mark({ ...msg, id: 'second-message' });

    const persisted = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    assert.equal(Object.keys(persisted).length, 1);
  });
});