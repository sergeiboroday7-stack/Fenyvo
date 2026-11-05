'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createOfflineMessageQueue } =
  require('../server_offline_message_queue');

function setup({ failWrite = false, initial = {} } = {}) {
  const queues = structuredClone(initial);
  const calls = [];
  const order = [];

  const service = createOfflineMessageQueue({
    getQueues: () => queues,

    saveQueues(next) {
      order.push('save');
      calls.push(structuredClone(next));

      if (failWrite) {
        throw new Error('SIMULATED_DISK_FAILURE');
      }

      return true;
    },

    commitRecipientQueue(username, next) {
      order.push('commit');
      queues[username] = next;
    },

    logger: () => {},
  });

  return { queues, calls, order, service };
}

const message = {
  id: 'm1',
  from: 'alice',
  to: 'bob',
  text: 'encrypted',
};

test('message is persisted before memory commit', () => {
  const h = setup();

  h.service.queueOfflineMessage('bob', message);

  assert.equal(h.calls.length, 1);
  assert.equal(h.calls[0].bob[0].id, 'm1');
  assert.equal(h.queues.bob[0].id, 'm1');
  assert.deepEqual(h.order, ['save', 'commit']);
});

test('failed write does not insert a message into RAM', () => {
  const h = setup({ failWrite: true });

  assert.throws(
    () => h.service.queueOfflineMessage('bob', message),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.calls.length, 1);
  assert.equal(h.queues.bob, undefined);
  assert.deepEqual(h.order, ['save']);
});

test('failed write preserves existing messages', () => {
  const oldMessage = {
    id: 'old',
    from: 'charlie',
    to: 'bob',
  };

  const h = setup({
    failWrite: true,
    initial: { bob: [oldMessage] },
  });

  const previous = h.queues.bob;

  assert.throws(
    () => h.service.queueOfflineMessage('bob', message),
    /SIMULATED_DISK_FAILURE/
  );

  assert.equal(h.queues.bob, previous);
  assert.equal(h.queues.bob.length, 1);
  assert.equal(h.queues.bob[0].id, 'old');
  assert.deepEqual(h.order, ['save']);
});

test('duplicate ID is not saved twice', () => {
  const h = setup({
    initial: { bob: [message] },
  });

  h.service.queueOfflineMessage('bob', message);

  assert.equal(h.calls.length, 0);
  assert.equal(h.queues.bob.length, 1);
  assert.deepEqual(h.order, []);
});

test('writing to bob does not change charlie queue', () => {
  const charlieMessage = {
    id: 'c1',
    from: 'alice',
    to: 'charlie',
  };

  const h = setup({
    initial: { charlie: [charlieMessage] },
  });

  const previous = h.queues.charlie;

  h.service.queueOfflineMessage('bob', message);

  assert.equal(h.queues.charlie, previous);
  assert.equal(h.queues.charlie.length, 1);
  assert.equal(h.queues.bob.length, 1);
});

test('save must complete before RAM commit', () => {
  const h = setup();

  h.service.queueOfflineMessage('bob', message);

  assert.deepEqual(h.order, ['save', 'commit']);
});