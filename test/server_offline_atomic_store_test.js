'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  createOfflineAtomicStore,
} = require('../server_offline_atomic_store');

function environment() {
  const dir = fs.mkdtempSync(
    path.join(os.tmpdir(), 'fenyvo-atomic-')
  );

  const filePath = path.join(dir, 'offline.json');

  return {
    dir,
    filePath,
    store: createOfflineAtomicStore({ filePath }),
    cleanup() {
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

const message = {
  id: 'm1',
  from: 'alice',
  to: 'bob',
  text: 'encrypted-payload',
};

test('atomic store saves and reloads original message', () => {
  const env = environment();

  try {
    const queue = { bob: [message] };

    assert.equal(env.store.save(queue), true);
    assert.deepEqual(env.store.load(), queue);
  } finally {
    env.cleanup();
  }
});

test('missing file loads as empty queue', () => {
  const env = environment();

  try {
    assert.deepEqual(env.store.load(), {});
  } finally {
    env.cleanup();
  }
});

test('corrupt JSON is rejected without overwriting it', () => {
  const env = environment();

  try {
    fs.writeFileSync(env.filePath, '{BROKEN', 'utf8');

    assert.throws(() => env.store.load());

    assert.equal(
      fs.readFileSync(env.filePath, 'utf8'),
      '{BROKEN'
    );
  } finally {
    env.cleanup();
  }
});

test('invalid queue cannot replace valid stored data', () => {
  const env = environment();

  try {
    env.store.save({ bob: [message] });

    assert.throws(() => env.store.save({ bob: null }));

    assert.equal(env.store.load().bob[0].id, 'm1');
  } finally {
    env.cleanup();
  }
});

test('failed rename preserves original data', () => {
  const env = environment();

  try {
    env.store.save({ bob: [message] });

    const before = fs.readFileSync(env.filePath, 'utf8');

    const brokenFs = {
      ...fs,
      renameSync() {
        throw new Error('SIMULATED_RENAME_FAILURE');
      },
    };

    const store = createOfflineAtomicStore({
      filePath: env.filePath,
      fsImpl: brokenFs,
    });

    assert.throws(
      () => store.save({ bob: [] }),
      /SIMULATED_RENAME_FAILURE/
    );

    assert.equal(
      fs.readFileSync(env.filePath, 'utf8'),
      before
    );

    assert.deepEqual(
      fs.readdirSync(env.dir),
      ['offline.json']
    );
  } finally {
    env.cleanup();
  }
});

test('failed write preserves original data', () => {
  const env = environment();

  try {
    env.store.save({ bob: [message] });

    const before = fs.readFileSync(env.filePath, 'utf8');

    const brokenFs = {
      ...fs,
      writeFileSync() {
        throw new Error('SIMULATED_WRITE_FAILURE');
      },
    };

    const store = createOfflineAtomicStore({
      filePath: env.filePath,
      fsImpl: brokenFs,
    });

    assert.throws(
      () => store.save({ bob: [] }),
      /SIMULATED_WRITE_FAILURE/
    );

    assert.equal(
      fs.readFileSync(env.filePath, 'utf8'),
      before
    );
  } finally {
    env.cleanup();
  }
});

test('successful replacement survives store recreation', () => {
  const env = environment();

  try {
    env.store.save({ bob: [message] });
    env.store.save({ bob: [] });

    const reopened = createOfflineAtomicStore({
      filePath: env.filePath,
    });

    assert.deepEqual(reopened.load(), { bob: [] });
  } finally {
    env.cleanup();
  }
});

test('temporary files are not left after success', () => {
  const env = environment();

  try {
    env.store.save({ bob: [message] });

    assert.deepEqual(
      fs.readdirSync(env.dir),
      ['offline.json']
    );
  } finally {
    env.cleanup();
  }
});