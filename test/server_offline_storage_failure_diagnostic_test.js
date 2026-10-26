'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, 'fixtures', 'legacy_offline_storage_failure_baseline.js'),
  'utf8'
);

function section(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);

  assert.ok(
    start >= 0 && end > start,
    `Missing source section: ${startMarker}`
  );

  return source.slice(start, end);
}

const loadSource = section(
  'function loadOfflineMessages(',
  'function saveOfflineMessages('
);

const saveSource = section(
  'function saveOfflineMessages(',
  'function loadMessageExpirations('
);

const purgeSource = section(
  'function purgeOfflineMessageArtifacts(',
  'function deletePrivateMessageForEveryone('
);

function createEnvironment(initialData = '{}') {
  let diskData = initialData;
  let failWrites = false;

  const sandbox = {
    OFFLINE_MESSAGES_FILE: 'offline-test.json',
    console: { error() {}, log() {} },
    fs: {
      existsSync: () => true,
      readFileSync: () => diskData,
      writeFileSync: (_name, value) => {
        if (failWrites) {
          throw new Error('SIMULATED_DISK_FAILURE');
        }
        diskData = value;
      },
    },
  };

  vm.createContext(sandbox);

  vm.runInContext(
    loadSource + '\n' + saveSource,
    sandbox,
    { timeout: 1000 }
  );

  return {
    sandbox,
    failWrites: value => { failWrites = value; },
    disk: () => diskData,
  };
}

test('baseline: successful offline save reaches disk', () => {
  const env = createEnvironment();

  const messages = {
    bob: [{
      id: 'm1',
      from: 'alice',
      to: 'bob',
    }],
  };

  env.sandbox.saveOfflineMessages(messages);

  assert.deepEqual(
    JSON.parse(env.disk()),
    messages
  );
});

test('diagnostic: disk write failure is swallowed', () => {
  const env = createEnvironment('{}');
  env.failWrites(true);

  const result = env.sandbox.saveOfflineMessages({
    bob: [{ id: 'm1', from: 'alice', to: 'bob' }],
  });

  assert.equal(result, undefined);
  assert.equal(env.disk(), '{}');
});

test('diagnostic: corrupt offline JSON loads as empty queue', () => {
  const env = createEnvironment('{broken-json');

  const result = env.sandbox.loadOfflineMessages();

  assert.deepEqual(
    JSON.parse(JSON.stringify(result)),
    {}
  );

  assert.equal(env.disk(), '{broken-json');
});

test('diagnostic: failed purge save leaves RAM and disk inconsistent', () => {
  const original = {
    bob: [{
      id: 'm1',
      from: 'alice',
      to: 'bob',
      text: 'ciphertext',
    }],
  };

  const env = createEnvironment(JSON.stringify(original));

  env.sandbox.offlineMessages = structuredClone(original);
  env.sandbox.offlineMessageStatus = {};
  env.sandbox.saveOfflineMessageStatus = () => {};

  vm.runInContext(purgeSource, env.sandbox, {
    timeout: 1000,
  });

  env.failWrites(true);

  const removed = env.sandbox.purgeOfflineMessageArtifacts(
    'bob',
    'm1'
  );

  assert.equal(removed, true);

  const inMemory = env.sandbox.offlineMessages;
  const onDisk = JSON.parse(env.disk());

  assert.equal(
    Array.isArray(inMemory.bob) ? inMemory.bob.length : 0,
    0
  );

  assert.equal(onDisk.bob.length, 1);
});
