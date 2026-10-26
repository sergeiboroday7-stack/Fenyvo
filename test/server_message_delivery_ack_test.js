'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const { createMessageDeliveryAck } =
  require('../server_message_delivery_ack');

const message = {
  id: 'secure-ack-message-123',
  from: 'alice',
  to: 'bob',
  text: 'hello',
};

function setup() {
  let saved = {};

  const store = {
    load: () => structuredClone(saved),
    save: next => { saved = structuredClone(next); },
  };

  const tx = createMessageTransaction({ store });
  tx.accept(message);

  const ack = createMessageDeliveryAck({
    transaction: tx,
    getAuthenticatedUser: socket => socket.user,
  });

  const data = {
    messageId: message.id,
    from: message.from,
    to: message.to,
  };

  return { tx, ack, data };
}

test('authenticated recipient can acknowledge', () => {
  const { tx, ack, data } = setup();

  const result = ack.acknowledge({ user: 'bob' }, data);

  assert.equal(result.accepted, true);
  assert.equal(result.duplicate, false);
  assert.equal(tx.pendingFor('bob').length, 0);
});

test('sender cannot acknowledge recipient message', () => {
  const { tx, ack, data } = setup();

  const result = ack.acknowledge({ user: 'alice' }, data);

  assert.equal(result.accepted, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('unrelated user cannot acknowledge', () => {
  const { tx, ack, data } = setup();

  const result = ack.acknowledge({ user: 'charlie' }, data);

  assert.equal(result.accepted, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('unauthenticated socket cannot acknowledge', () => {
  const { tx, ack, data } = setup();

  const result = ack.acknowledge({}, data);

  assert.equal(result.reason, 'unauthenticated');
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('forged sender cannot erase pending message', () => {
  const { tx, ack, data } = setup();

  const result = ack.acknowledge(
    { user: 'bob' },
    { ...data, from: 'charlie' }
  );

  assert.equal(result.accepted, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('unknown ID cannot be acknowledged', () => {
  const { tx, ack, data } = setup();

  const result = ack.acknowledge(
    { user: 'bob' },
    { ...data, messageId: 'unknown-id-123' }
  );

  assert.equal(result.accepted, false);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('second acknowledgement is idempotent', () => {
  const { tx, ack, data } = setup();

  ack.acknowledge({ user: 'bob' }, data);

  const second = ack.acknowledge({ user: 'bob' }, data);

  assert.deepEqual(second, {
    accepted: true,
    duplicate: true,
  });

  assert.equal(tx.pendingFor('bob').length, 0);
});

test('malformed acknowledgement is rejected', () => {
  const { tx, ack } = setup();

  const result = ack.acknowledge(
    { user: 'bob' },
    { messageId: '', from: 'alice', to: 'bob' }
  );

  assert.equal(result.reason, 'invalid');
  assert.equal(tx.pendingFor('bob').length, 1);
});