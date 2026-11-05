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

function extract(start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `Missing section: ${start}`);
  return source.slice(a, b);
}

const functions =
  extract(
    'function loadOfflineMessageStatus()',
    'function sendOrQueueMessageStatus('
  ) +
  '\n' +
  extract(
    'function deliverOfflineMessageStatus(',
    '// FENYVO AI AUTO CONVERSATION SETTINGS'
  );

function setup(initial = {}) {
  let disk = structuredClone(initial);
  let failWrite = false;
  const sent = [];

  const sandbox = {
    OFFLINE_MESSAGE_STATUS_FILE: 'test-status.json',
    offlineMessageStatus: structuredClone(initial),
    WebSocket: { OPEN: 1 },
    console: { log() {} },
    send(_ws, type, data) {
      sent.push({ type, data });
    },
    createOfflineAtomicStore() {
      return {
        load() {
          return structuredClone(disk);
        },
        save(next) {
          if (failWrite) throw new Error('SIMULATED_DISK_FAILURE');
          disk = structuredClone(next);
          return true;
        },
      };
    },
  };

  vm.createContext(sandbox);
  vm.runInContext(functions, sandbox);

  return {
    sandbox,
    disk: () => disk,
    sent,
    failWrites(value) {
      failWrite = value;
    },
  };
}

test('failed status save keeps memory unchanged', () => {
  const h = setup({ bob: [] });
  h.failWrites(true);

  assert.throws(
    () => h.sandbox.queueOfflineMessageStatus(
      'bob', 'message_delivered', { messageId: 'm1' }
    ),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.sandbox.offlineMessageStatus.bob.length, 0);
  assert.equal(h.disk().bob.length, 0);
});

test('read status replaces delivered status durably', () => {
  const h = setup();
  h.sandbox.queueOfflineMessageStatus(
    'bob', 'message_delivered', { messageId: 'm1' }
  );
  h.sandbox.queueOfflineMessageStatus(
    'bob', 'message_read', { messageId: 'm1' }
  );

  assert.equal(h.disk().bob.length, 1);
  assert.equal(h.disk().bob[0].type, 'message_read');
  assert.equal(h.sandbox.offlineMessageStatus.bob.length, 1);
});

test('failed status retirement preserves retry queue', () => {
  const h = setup({
    bob: [{ type: 'message_read', data: { messageId: 'm1' } }],
  });
  h.failWrites(true);

  assert.throws(
    () => h.sandbox.deliverOfflineMessageStatus(
      'bob', { readyState: 1 }
    ),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.sandbox.offlineMessageStatus.bob.length, 1);
  assert.equal(h.disk().bob.length, 1);
  assert.equal(h.sent.length, 1);
});

test('successful status retirement clears persisted queue', () => {
  const h = setup({
    bob: [{ type: 'message_read', data: { messageId: 'm1' } }],
  });

  h.sandbox.deliverOfflineMessageStatus(
    'bob', { readyState: 1 }
  );

  assert.equal(h.disk().bob, undefined);
  assert.equal(h.sandbox.offlineMessageStatus.bob, undefined);
  assert.equal(h.sent.length, 1);
});