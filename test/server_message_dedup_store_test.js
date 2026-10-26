'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createDedupStore } = require('../server_message_dedup_store');

function withTempStore(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-dedup-'));
  const file = path.join(dir, 'message_dedup.json');

  try {
    fn({ file, dir, store: createDedupStore(file) });
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('missing store loads empty records', () => {
  withTempStore(({ store }) => {
    assert.deepEqual(store.load(), {});
  });
});

test('records survive recreating the store', () => {
  withTempStore(({ store, file }) => {
    const records = { 'message-123': 123456789 };

    store.save(records);

    const reopened = createDedupStore(file);
    assert.deepEqual(reopened.load(), records);
  });
});

test('new records replace old records', () => {
  withTempStore(({ store }) => {
    store.save({ old: 1 });
    store.save({ next: 2 });

    assert.deepEqual(store.load(), { next: 2 });
  });
});

test('invalid JSON produces an explicit failure', () => {
  withTempStore(({ store, file }) => {
    fs.writeFileSync(file, '{invalid json');

    assert.throws(() => store.load(), SyntaxError);
  });
});

test('write errors propagate without pretending success', () => {
  const fakeFs = {
    existsSync: () => false,
    writeFileSync: () => {
      throw Object.assign(new Error('disk full'), { code: 'ENOSPC' });
    },
    renameSync: () => {
      throw new Error('unexpected rename');
    },
    unlinkSync: () => {},
  };

  const store = createDedupStore(
    path.join(os.tmpdir(), 'isolated-dedup.json'),
    { filesystem: fakeFs }
  );

  assert.throws(
    () => store.save({ a: 1 }),
    error => error.code === 'ENOSPC'
  );
});

test('failed replacement leaves original store intact', () => {
  withTempStore(({ file, store }) => {
    store.save({ original: 10 });

    const fakeFs = {
      ...fs,
      renameSync: () => {
        throw new Error('simulated rename failure');
      },
    };

    const failingStore = createDedupStore(file, {
      filesystem: fakeFs,
    });

    assert.throws(() => failingStore.save({ replaced: 20 }));
    assert.deepEqual(store.load(), { original: 10 });
  });
});