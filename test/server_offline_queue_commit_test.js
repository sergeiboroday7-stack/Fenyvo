'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'), 'utf8'
);

const start = source.indexOf('function queueOfflineMessage(');
const end = source.indexOf('function queueOfflineEvent(', start);

assert.ok(start >= 0 && end > start);

const functionSource = source.slice(start, end);

function setup({ failWrite = false, initial = {} } = {}) {
  const offlineMessages = structuredClone(initial);
  const calls = [];

  const sandbox = {
    offlineMessages,
    saveOfflineMessages(messages) {
      calls.push(structuredClone(messages));

      if (failWrite) {
        throw new Error('SIMULATED_DISK_FAILURE');
      }

      return true;
    },
    console: { log() {} },
  };

  vm.createContext(sandbox);
  vm.runInContext(functionSource, sandbox);

  return {
    sandbox,
    calls,
    offlineMessages,
  };
}

const message = {
  id: 'm1',
  from: 'alice',
  to: 'bob',
  text: 'encrypted',
};

test('new message is persisted before memory commit', () => {
  const h = setup();

  h.sandbox.queueOfflineMessage('bob', message);

  assert.equal(h.calls.length, 1);
  assert.equal(h.calls[0].bob[0].id, 'm1');
  assert.equal(h.offlineMessages.bob[0].id, 'm1');
});

test('failed write never inserts message into RAM queue', () => {
  const h = setup({ failWrite: true });

  assert.throws(
    () => h.sandbox.queueOfflineMessage('bob', message),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.calls.length, 1);
  assert.equal(h.offlineMessages.bob, undefined);
});

test('failed write preserves existing recipient messages', () => {
  const oldMessage = {
    id: 'old',
    from: 'charlie',
    to: 'bob',
  };

  const h = setup({
    failWrite: true,
    initial: { bob: [oldMessage] },
  });

  const priorReference = h.offlineMessages.bob;

  assert.throws(
    () => h.sandbox.queueOfflineMessage('bob', message),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.offlineMessages.bob, priorReference);
  assert.equal(h.offlineMessages.bob.length, 1);
  assert.equal(h.offlineMessages.bob[0].id, 'old');
});

test('duplicate ID does not write or duplicate message', () => {
  const h = setup({
    initial: { bob: [message] },
  });

  h.sandbox.queueOfflineMessage('bob', message);

  assert.equal(h.calls.length, 0);
  assert.equal(h.offlineMessages.bob.length, 1);
});

test('saving bob does not modify charlie queue', () => {
  const charlieMessage = {
    id: 'c1',
    from: 'alice',
    to: 'charlie',
  };

  const h = setup({
    initial: { charlie: [charlieMessage] },
  });

  const charlieReference = h.offlineMessages.charlie;

  h.sandbox.queueOfflineMessage('bob', message);

  assert.equal(h.offlineMessages.charlie, charlieReference);
  assert.equal(h.offlineMessages.charlie.length, 1);
  assert.equal(h.offlineMessages.bob.length, 1);
});

test('source commits RAM only after successful save', () => {
  const save = functionSource.indexOf('saveOfflineMessages(nextMessages)');
  const commit = functionSource.indexOf(
    'offlineMessages[username] = nextRecipientQueue'
  );

  assert.ok(save >= 0);
  assert.ok(commit > save);
});