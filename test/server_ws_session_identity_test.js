'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createServerSessionIdentity } =
  require('../server_ws_session_identity');

const { createMessageTransaction } =
  require('../server_message_transaction');

const { createMessageDeliveryAck } =
  require('../server_message_delivery_ack');

function createStore() {
  let records = {};

  return {
    load: () => structuredClone(records),
    save: next => { records = structuredClone(next); },
  };
}

test('unbound socket has no authenticated identity', () => {
  const identity = createServerSessionIdentity();
  assert.equal(identity.getAuthenticatedUser({}), null);
});

test('forged socket.user property cannot authenticate', () => {
  const identity = createServerSessionIdentity();
  const socket = { user: 'bob' };

  assert.equal(identity.getAuthenticatedUser(socket), null);
});

test('server-bound identity cannot be replaced by property mutation', () => {
  const identity = createServerSessionIdentity();
  const socket = { user: 'charlie' };

  identity.bindAuthenticated(socket, 'bob');
  socket.user = 'alice';

  assert.equal(identity.getAuthenticatedUser(socket), 'bob');
});

test('authenticated identity cannot be rebound silently', () => {
  const identity = createServerSessionIdentity();
  const socket = {};

  identity.bindAuthenticated(socket, 'bob');

  assert.throws(
    () => identity.bindAuthenticated(socket, 'alice'),
    /already bound/
  );

  assert.equal(identity.getAuthenticatedUser(socket), 'bob');
});

test('different connections retain separate identities', () => {
  const identity = createServerSessionIdentity();
  const bob = {};
  const alice = {};

  identity.bindAuthenticated(bob, 'bob');
  identity.bindAuthenticated(alice, 'alice');

  assert.equal(identity.getAuthenticatedUser(bob), 'bob');
  assert.equal(identity.getAuthenticatedUser(alice), 'alice');
});

test('revoked session loses authorization', () => {
  const identity = createServerSessionIdentity();
  const socket = {};

  identity.bindAuthenticated(socket, 'bob');

  assert.equal(identity.revoke(socket), true);
  assert.equal(identity.getAuthenticatedUser(socket), null);
});

test('invalid identities are rejected', () => {
  const identity = createServerSessionIdentity();

  for (const user of ['', ' bob ', 42, null, 'x'.repeat(129)]) {
    assert.throws(
      () => identity.bindAuthenticated({}, user),
      TypeError
    );
  }
});

test('forged ACK cannot bypass server-bound session identity', () => {
  const identity = createServerSessionIdentity();
  const tx = createMessageTransaction({ store: createStore() });

  const message = {
    id: 'security-session-message-123',
    from: 'alice',
    to: 'bob',
    text: 'protected',
  };

  tx.accept(message);

  const ack = createMessageDeliveryAck({
    transaction: tx,
    getAuthenticatedUser: socket =>
      identity.getAuthenticatedUser(socket),
  });

  const request = {
    messageId: message.id,
    from: 'alice',
    to: 'bob',
    user: 'bob',
  };

  const attacker = { user: 'bob' };
  identity.bindAuthenticated(attacker, 'charlie');

  assert.equal(
    ack.acknowledge(attacker, request).accepted,
    false
  );

  assert.equal(tx.pendingFor('bob').length, 1);

  const recipient = {};
  identity.bindAuthenticated(recipient, 'bob');

  assert.equal(
    ack.acknowledge(recipient, request).accepted,
    true
  );

  assert.equal(tx.pendingFor('bob').length, 0);

  identity.revoke(recipient);

  assert.equal(
    ack.acknowledge(recipient, request).reason,
    'unauthenticated'
  );
});