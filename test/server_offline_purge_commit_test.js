'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

const start = source.indexOf(
  'function purgeOfflineMessageArtifacts('
);

const end = source.indexOf(
  'function deletePrivateMessageForEveryone(',
  start
);

assert.ok(start >= 0 && end > start);

const functionSource = source.slice(start, end);

function setup({
  initial = {},
  statuses = {},
  failWrite = false,
} = {}) {
  const offlineMessages = structuredClone(initial);
  const offlineMessageStatus = structuredClone(statuses);
  const saves = [];

  const sandbox = {
    offlineMessages,
    offlineMessageStatus,

    saveOfflineMessages(next) {
      if (failWrite) {
        throw new Error('SIMULATED_DISK_FAILURE');
      }

      saves.push(structuredClone(next));
      return true;
    },

    saveOfflineMessageStatus() {
      return true;
    },
  };

  vm.createContext(sandbox);
  vm.runInContext(functionSource, sandbox);

  return {
    sandbox,
    offlineMessages,
    offlineMessageStatus,
    saves,
  };
}

const message = {
  id: 'm1',
  from: 'alice',
  to: 'bob',
  text: 'ciphertext',
};

test('successful purge persists and clears message', () => {
  const h = setup({
    initial: { bob: [message] },
  });

  const removed = h.sandbox.purgeOfflineMessageArtifacts(
    'bob',
    'm1'
  );

  assert.equal(removed, true);
  assert.equal(h.saves.length, 1);
  assert.equal(h.offlineMessages.bob, undefined);
  assert.equal(h.saves[0].bob, undefined);
});

test('disk failure retains original message in memory', () => {
  const h = setup({
    initial: { bob: [message] },
    failWrite: true,
  });

  const before = h.offlineMessages.bob;

  assert.throws(
    () => h.sandbox.purgeOfflineMessageArtifacts('bob', 'm1'),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.offlineMessages.bob, before);
  assert.equal(h.offlineMessages.bob.length, 1);
  assert.equal(h.offlineMessages.bob[0].id, 'm1');
});

test('purging one message preserves another', () => {
  const other = {
    id: 'm2',
    from: 'charlie',
    to: 'bob',
  };

  const h = setup({
    initial: { bob: [message, other] },
  });

  h.sandbox.purgeOfflineMessageArtifacts('bob', 'm1');

  assert.equal(h.offlineMessages.bob.length, 1);
  assert.equal(h.offlineMessages.bob[0].id, 'm2');
  assert.equal(h.saves[0].bob[0].id, 'm2');
});

test('disk failure retains all recipient queues', () => {
  const h = setup({
    initial: {
      bob: [message],
      charlie: [{
        id: 'c1',
        from: 'alice',
        to: 'charlie',
      }],
    },
    failWrite: true,
  });

  const before = structuredClone(h.offlineMessages);

  assert.throws(
    () => h.sandbox.purgeOfflineMessageArtifacts('bob', 'm1'),
    /SIMULATED_DISK_FAILURE/
  );

  assert.deepEqual(h.offlineMessages, before);
  assert.equal(h.saves.length, 0);
});

test('unknown message does not modify queued originals', () => {
  const h = setup({
    initial: { bob: [message] },
  });

  const removed = h.sandbox.purgeOfflineMessageArtifacts(
    'bob',
    'unknown'
  );

  assert.equal(removed, false);
  assert.equal(h.saves.length, 0);
  assert.equal(h.offlineMessages.bob.length, 1);
});

test('related reply cleanup happens after successful save', () => {
  const reply = {
    id: 'reply1',
    from: 'charlie',
    to: 'bob',
    replyTo: {
      id: 'm1',
      from: 'alice',
    },
  };

  const h = setup({
    initial: { bob: [message, reply] },
  });

  h.sandbox.purgeOfflineMessageArtifacts('bob', 'm1');

  assert.equal(h.offlineMessages.bob.length, 1);
  assert.equal(h.offlineMessages.bob[0].replyTo, undefined);
  assert.equal(h.saves[0].bob[0].replyTo, undefined);
});

test('purge writes before RAM commit', () => {
  const save = functionSource.indexOf(
    'saveOfflineMessages(nextMessages)'
  );

  const commit = functionSource.indexOf(
    'offlineMessages[username] = nextQueue'
  );

  assert.ok(save >= 0);
  assert.ok(commit > save);
});