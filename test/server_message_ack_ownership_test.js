'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  verifyMessageAckOwnership,
} = require('../server_message_ack_ownership');

const saved = {
  id: 'm-123',
  from: 'alice',
  to: 'bob',
  text: 'encrypted',
};

function check(overrides = {}) {
  return verifyMessageAckOwnership({
    authenticatedUser: 'bob',
    messageId: 'm-123',
    from: 'alice',
    to: 'bob',
    queue: [saved],
    ...overrides,
  });
}

test('genuine recipient can confirm stored message', () => {
  assert.equal(check().allowed, true);
});

test('different authenticated user is rejected', () => {
  assert.equal(
    check({ authenticatedUser: 'mallory' }).reason,
    'forbidden'
  );
});

test('forged sender is rejected', () => {
  assert.equal(
    check({ from: 'mallory' }).reason,
    'identity_mismatch'
  );
});

test('forged recipient is rejected', () => {
  assert.equal(
    check({ to: 'mallory' }).reason,
    'forbidden'
  );
});

test('unknown message cannot be acknowledged', () => {
  assert.equal(
    check({ messageId: 'missing' }).reason,
    'not_found'
  );
});

test('another sender message cannot be removed by same ID', () => {
  assert.equal(
    check({
      queue: [{ ...saved, from: 'charlie' }],
    }).reason,
    'identity_mismatch'
  );
});

test('ambiguous duplicate ID fails closed', () => {
  assert.equal(
    check({ queue: [saved, { ...saved }] }).reason,
    'ambiguous'
  );
});

test('queued events are not treated as original messages', () => {
  assert.equal(
    check({
      queue: [{
        ...saved,
        __eventType: 'message_edited',
      }],
    }).reason,
    'not_found'
  );
});

test('missing or malformed queue is rejected', () => {
  assert.equal(check({ queue: null }).allowed, false);
  assert.equal(check({ queue: {} }).allowed, false);
});

test('missing identity fields are rejected', () => {
  assert.equal(check({ from: '' }).reason, 'invalid');
  assert.equal(check({ messageId: '' }).reason, 'invalid');
});

test('ownership verification does not mutate queue', () => {
  const queue = [structuredClone(saved)];
  const before = structuredClone(queue);

  check({ queue });

  assert.deepEqual(queue, before);
});

test('empty queue cannot remove a message', () => {
  assert.equal(
    check({ queue: [] }).reason,
    'not_found'
  );
});