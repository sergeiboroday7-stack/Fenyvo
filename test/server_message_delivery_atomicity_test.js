'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

// Isolated failure model, NOT an integration test of server.js.
// Demonstrates why independently persisted dedup and queue
// cannot safely be treated as one committed operation.

const identity = {
  from: 'alice',
  to: 'bob',
  id: '1234567890123456-abcdef0123456789',
};

function createModel() {
  const processed = new Set();
  const queued = new Set();

  function sendWithDedupFirst(message, { queueFails = false } = {}) {
    if (processed.has(message.id)) return 'duplicate';
    processed.add(message.id);

    if (queueFails) throw new Error('queue write failed');

    queued.add(message.id);
    return 'accepted';
  }

  function sendWithQueueFirst(message, { dedupFails = false } = {}) {
    if (processed.has(message.id)) return 'duplicate';

    queued.add(message.id);

    if (dedupFails) throw new Error('dedup write failed');

    processed.add(message.id);
    return 'accepted';
  }

  return { processed, queued, sendWithDedupFirst, sendWithQueueFirst };
}

test('dedup-first failure can suppress a missing message on retry', () => {
  const model = createModel();

  assert.throws(
    () => model.sendWithDedupFirst(identity, { queueFails: true }),
    /queue write failed/
  );

  assert.equal(model.processed.has(identity.id), true);
  assert.equal(model.queued.has(identity.id), false);

  assert.equal(model.sendWithDedupFirst(identity), 'duplicate');
  assert.equal(model.queued.has(identity.id), false);
});

test('queue-first failure can leave a message without dedup state', () => {
  const model = createModel();

  assert.throws(
    () => model.sendWithQueueFirst(identity, { dedupFails: true }),
    /dedup write failed/
  );

  assert.equal(model.queued.has(identity.id), true);
  assert.equal(model.processed.has(identity.id), false);
});

test('successful separate writes do not prove crash atomicity', () => {
  const model = createModel();

  assert.equal(model.sendWithQueueFirst(identity), 'accepted');
  assert.equal(model.queued.has(identity.id), true);
  assert.equal(model.processed.has(identity.id), true);

  // This only proves the no-failure path in the model.
  // It does NOT establish durability across process crashes.
});