'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'), 'utf8'
);

const loadStart = source.indexOf('function loadOfflineMessages()');
const saveStart = source.indexOf('function saveOfflineMessages(');
const end = source.indexOf('function loadMessageExpirations(', saveStart);

assert.ok(loadStart >= 0 && saveStart > loadStart && end > saveStart);

const functions = source.slice(loadStart, end);

function setup({
  loadResult = {},
  loadError = null,
  saveError = null,
} = {}) {
  const state = { saves: [] };

  const sandbox = {
    OFFLINE_MESSAGES_FILE: 'isolated-offline.json',
    createOfflineAtomicStore({ filePath }) {
      assert.equal(filePath, 'isolated-offline.json');

      return {
        load() {
          if (loadError) throw loadError;
          return loadResult;
        },
        save(messages) {
          if (saveError) throw saveError;
          state.saves.push(messages);
          return true;
        },
      };
    },
  };

  vm.createContext(sandbox);
  vm.runInContext(functions, sandbox);

  return { sandbox, state };
}

test('server loads queue through atomic store', () => {
  const queue = { bob: [{ id: 'm1' }] };
  const { sandbox } = setup({ loadResult: queue });

  assert.deepEqual(sandbox.loadOfflineMessages(), queue);
});

test('corrupt storage error propagates during load', () => {
  const { sandbox } = setup({
    loadError: new SyntaxError('CORRUPT_QUEUE'),
  });

  assert.throws(
    () => sandbox.loadOfflineMessages(),
    /CORRUPT_QUEUE/
  );
});

test('server saves queue through atomic store', () => {
  const { sandbox, state } = setup();
  const queue = { bob: [{ id: 'm1' }] };

  assert.equal(sandbox.saveOfflineMessages(queue), true);
  assert.equal(state.saves.length, 1);
  assert.equal(state.saves[0], queue);
});

test('disk failure propagates during save', () => {
  const { sandbox } = setup({
    saveError: new Error('SIMULATED_DISK_FAILURE'),
  });

  assert.throws(
    () => sandbox.saveOfflineMessages({ bob: [] }),
    /SIMULATED_DISK_FAILURE/
  );
});

test('main server imports atomic storage module', () => {
  assert.match(
    source,
    /require\('\.\/server_offline_atomic_store'\)/
  );
});

test('message delivery ownership protection is preserved', () => {
  assert.match(
    source,
    /verifyMessageAckOwnership\(\{/
  );
  assert.match(
    source,
    /wsSessionIdentity\.getAuthenticatedUser\(ws\)/
  );
});