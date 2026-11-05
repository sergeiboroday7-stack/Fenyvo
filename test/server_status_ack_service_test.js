'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createStatusAckService } =
  require('../server_status_ack_service');

function fixture() {
  const ws = {};
  const otherWs = {};
  let queues = {
    alice: [
      { type: 'message_delivered', data: { messageId: 'm1' } },
      { type: 'message_read', data: { messageId: 'm2' } },
    ],
  };
  let failSave = false;
  let saveCalls = 0;

  const service = createStatusAckService({
    getQueues: () => queues,
    saveQueues: next => {
      saveCalls++;
      if (failSave) throw new Error('disk failure');
    },
    commitQueue: (user, remaining) => {
      const next = { ...queues };
      if (remaining.length) next[user] = remaining;
      else delete next[user];
      queues = next;
    },
    getAuthenticatedUser: socket =>
      socket === ws ? 'alice' : 'bob',
    isCurrentSocket: (user, socket) =>
      user === 'alice' && socket === ws,
  });

  return {
    ws, otherWs, service,
    get queues() { return queues; },
    get saveCalls() { return saveCalls; },
    fail: () => { failSave = true; },
  };
}

test('valid ACK removes only matching status', () => {
  const f = fixture();
  const result = f.service.acknowledge({
    ws: f.ws, username: 'alice',
    messageId: 'm1', type: 'message_delivered',
  });
  assert.equal(result.accepted, true);
  assert.equal(f.queues.alice.length, 1);
  assert.equal(f.queues.alice[0].data.messageId, 'm2');
});

test('different user cannot acknowledge', () => {
  const f = fixture();
  const result = f.service.acknowledge({
    ws: f.otherWs, username: 'alice',
    messageId: 'm1', type: 'message_delivered',
  });
  assert.equal(result.accepted, false);
  assert.equal(f.queues.alice.length, 2);
  assert.equal(f.saveCalls, 0);
});

test('duplicate ACK is idempotent', () => {
  const f = fixture();
  const args = {
    ws: f.ws, username: 'alice',
    messageId: 'm1', type: 'message_delivered',
  };
  assert.equal(f.service.acknowledge(args).accepted, true);
  assert.equal(f.service.acknowledge(args).accepted, false);
  assert.equal(f.saveCalls, 1);
});

test('wrong status type cannot remove entry', () => {
  const f = fixture();
  const result = f.service.acknowledge({
    ws: f.ws, username: 'alice',
    messageId: 'm1', type: 'message_read',
  });
  assert.equal(result.accepted, false);
  assert.equal(f.queues.alice.length, 2);
});

test('disk error preserves memory queue', () => {
  const f = fixture();
  f.fail();
  assert.throws(() => f.service.acknowledge({
    ws: f.ws, username: 'alice',
    messageId: 'm1', type: 'message_delivered',
  }), /disk failure/);
  assert.equal(f.queues.alice.length, 2);
});

test('last ACK removes empty recipient queue', () => {
  const f = fixture();
  for (const [id, type] of [
    ['m1', 'message_delivered'],
    ['m2', 'message_read'],
  ]) {
    assert.equal(f.service.acknowledge({
      ws: f.ws, username: 'alice',
      messageId: id, type,
    }).accepted, true);
  }
  assert.equal(Object.hasOwn(f.queues, 'alice'), false);
});

test('invalid ACK does not write', () => {
  const f = fixture();
  const result = f.service.acknowledge({
    ws: f.ws, username: 'alice',
    messageId: '', type: 'message_read',
  });
  assert.equal(result.accepted, false);
  assert.equal(f.saveCalls, 0);
});