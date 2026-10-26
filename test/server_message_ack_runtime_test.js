'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'), 'utf8'
);

const startMarker = '// MESSAGE DELIVERED';
const endMarker = '// MESSAGE READ';

const start = source.indexOf(startMarker);
const end = source.indexOf(endMarker, start + startMarker.length);

assert.ok(start >= 0 && end > start, 'ACK handler markers missing');

const section = source.slice(start + startMarker.length, end);

assert.match(section, /verifyMessageAckOwnership/);
assert.match(section, /purgeOfflineMessageArtifacts/);

const { verifyMessageAckOwnership } =
  require('../server_message_ack_ownership');

function setup({
  authenticatedUser = 'bob',
  currentUser = 'bob',
  requestFrom = 'alice',
  requestTo = 'bob',
  requestId = 'message-123',
  queue = [{
    id: 'message-123',
    from: 'alice',
    to: 'bob',
    text: 'encrypted',
  }],
} = {}) {
  const state = {
    queue: structuredClone(queue),
    purged: [],
    statuses: [],
    errors: [],
  };

  const offlineMessages = { bob: state.queue };

  const sandbox = {
    type: 'message_delivered',
    data: {
      messageId: requestId,
      from: requestFrom,
      to: requestTo,
    },
    currentUser,
    ws: {},
    registeredUsers: {
      alice: {},
      bob: {},
      mallory: {},
    },
    offlineMessages,
    verifyMessageAckOwnership,
    wsSessionIdentity: {
      getAuthenticatedUser: () => authenticatedUser,
    },
    purgeOfflineMessageArtifacts(to, id) {
      state.purged.push({ to, id });
      offlineMessages[to] =
        (offlineMessages[to] || []).filter(item => item.id !== id);
    },
    sendOrQueueMessageStatus(user, event, data) {
      state.statuses.push({
        user,
        event,
        data: structuredClone(data),
      });
    },
    send(_ws, event, data) {
      state.errors.push({ event, data });
    },
    console: { log() {} },
  };

  const handler = vm.runInNewContext(
    `(async function executeAck() {
      ${section}
    })`,
    sandbox,
    { timeout: 1000 }
  );

  return {
    state,
    run: () => handler(),
  };
}

test('actual handler accepts genuine delivery ACK', async () => {
  const h = setup();
  await h.run();

  assert.equal(h.state.purged.length, 1);
  assert.equal(h.state.statuses.length, 1);
  assert.equal(h.state.statuses[0].user, 'alice');
  assert.equal(h.state.statuses[0].event, 'message_delivered');
});

test('actual handler rejects forged sender', async () => {
  const h = setup({ requestFrom: 'mallory' });
  await h.run();

  assert.equal(h.state.purged.length, 0);
  assert.equal(h.state.statuses.length, 0);
  assert.equal(h.state.queue.length, 1);
});

test('actual handler rejects forged session identity', async () => {
  const h = setup({ authenticatedUser: 'mallory' });
  await h.run();

  assert.equal(h.state.purged.length, 0);
  assert.equal(h.state.statuses.length, 0);
});

test('actual handler rejects unknown message ID', async () => {
  const h = setup({ requestId: 'missing-id' });
  await h.run();

  assert.equal(h.state.purged.length, 0);
  assert.equal(h.state.statuses.length, 0);
});

test('actual handler does not emit duplicate delivery ACK', async () => {
  const h = setup();

  await h.run();
  await h.run();

  assert.equal(h.state.purged.length, 1);
  assert.equal(h.state.statuses.length, 1);
});

test('actual handler rejects recipient mismatch', async () => {
  const h = setup({ requestTo: 'mallory' });
  await h.run();

  assert.equal(h.state.purged.length, 0);
  assert.equal(h.state.statuses.length, 0);
});

test('actual handler rejects revoked authentication', async () => {
  const h = setup({ authenticatedUser: null });
  await h.run();

  assert.equal(h.state.purged.length, 0);
  assert.equal(h.state.statuses.length, 0);
});

test('actual handler rejects duplicate queued identity', async () => {
  const message = {
    id: 'message-123',
    from: 'alice',
    to: 'bob',
  };

  const h = setup({ queue: [message, { ...message }] });
  await h.run();

  assert.equal(h.state.purged.length, 0);
  assert.equal(h.state.statuses.length, 0);
});