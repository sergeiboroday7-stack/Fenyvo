'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createOfflineMessageQueue } =
  require('../server_offline_message_queue');

function setup() {
  const queues = {};
  const writes = [];
  const logs = [];

  const service = createOfflineMessageQueue({
    getQueues: () => queues,
    saveQueues: (next) => writes.push(next),
    commitRecipientQueue: (username, next) => {
      queues[username] = next;
    },
    logger: (message) => logs.push(message),
  });

  return { queues, writes, logs, service };
}

test('queues a message and persists before commit', () => {
  const ctx = setup();
  const message = { id: 'message-1', to: 'bob' };

  ctx.service.queueOfflineMessage('bob', message);

  assert.equal(ctx.writes.length, 1);
  assert.equal(ctx.queues.bob.length, 1);
  assert.equal(ctx.queues.bob[0], message);
});

test('same ID does not create a duplicate', () => {
  const ctx = setup();
  const message = { id: 'message-2', to: 'bob' };

  ctx.service.queueOfflineMessage('bob', message);
  ctx.service.queueOfflineMessage('bob', message);

  assert.equal(ctx.writes.length, 1);
  assert.equal(ctx.queues.bob.length, 1);
});

test('write failure keeps active queue unchanged', () => {
  const queues = { bob: [{ id: 'old' }] };
  const initial = queues.bob;

  const service = createOfflineMessageQueue({
    getQueues: () => queues,
    saveQueues: () => { throw new Error('disk failure'); },
    commitRecipientQueue: (user, items) => {
      queues[user] = items;
    },
    logger: () => {},
  });

  assert.throws(
    () => service.queueOfflineMessage(
      'bob', { id: 'new', to: 'bob' }
    ),
    /disk failure/
  );

  assert.equal(queues.bob, initial);
  assert.equal(queues.bob.length, 1);
});

test('same ID for different recipients stays separate', () => {
  const ctx = setup();

  ctx.service.queueOfflineMessage(
    'bob', { id: 'shared', to: 'bob' }
  );

  ctx.service.queueOfflineMessage(
    'alice', { id: 'shared', to: 'alice' }
  );

  assert.equal(ctx.queues.bob.length, 1);
  assert.equal(ctx.queues.alice.length, 1);
  assert.equal(ctx.writes.length, 2);
});