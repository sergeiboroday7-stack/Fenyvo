'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const WebSocket = require('ws');
const { WebSocketServer } = require('ws');

const { createMessageTransaction } =
  require('../server_message_transaction');

const { createMessageDeliveryAck } =
  require('../server_message_delivery_ack');

const { createServerSessionIdentity } =
  require('../server_ws_session_identity');

test('WebSocket ACK rejects impersonation and revoked sessions', {
  timeout: 15000,
}, async () => {
  let saved = {};

  const store = {
    load: () => structuredClone(saved),
    save: next => { saved = structuredClone(next); },
  };

  const tx = createMessageTransaction({ store });
  const identity = createServerSessionIdentity();

  const message = {
    id: 'ws-security-ack-123',
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

  const wss = new WebSocketServer({
    host: '127.0.0.1',
    port: 0,
  });

  const clients = [];
  let connectionNumber = 0;

  wss.on('connection', socket => {
    connectionNumber++;

    // Identities are assigned by the test server,
    // not from WebSocket client messages.
    if (connectionNumber === 1) {
      identity.bindAuthenticated(socket, 'charlie');
    }

    if (connectionNumber === 2) {
      identity.bindAuthenticated(socket, 'bob');
    }

    socket.on('message', raw => {
      let result;

      try {
        const frame = JSON.parse(raw.toString());

        if (frame.type === 'revoke_session') {
          identity.revoke(socket);
          result = { revoked: true };
        } else if (frame.type === 'message_delivered') {
          result = ack.acknowledge(socket, frame.data);
        } else {
          result = { accepted: false, reason: 'unknown_type' };
        }
      } catch {
        result = { accepted: false, reason: 'bad_frame' };
      }

      socket.send(JSON.stringify(result));
    });

    socket.on('close', () => identity.revoke(socket));
  });

  async function connect(port) {
    const client = new WebSocket(`ws://127.0.0.1:${port}`);
    clients.push(client);
    await once(client, 'open');
    return client;
  }

  async function request(client, type, data) {
    const response = once(client, 'message');
    client.send(JSON.stringify({ type, data }));

    const [raw] = await response;
    return JSON.parse(raw.toString());
  }

  const payload = {
    messageId: message.id,
    from: 'alice',
    to: 'bob',
    user: 'bob',
  };

  try {
    if (!wss.address()) await once(wss, 'listening');
    const port = wss.address().port;

    const attacker = await connect(port);
    const bob = await connect(port);
    const anonymous = await connect(port);

    // 1. Attacker claims to be bob using JSON fields.
    const forged = await request(
      attacker,
      'message_delivered',
      payload
    );

    assert.equal(forged.accepted, false);
    assert.equal(tx.pendingFor('bob').length, 1);

    // 2. Unauthenticated connection cannot ACK.
    const unauthenticated = await request(
      anonymous,
      'message_delivered',
      payload
    );

    assert.equal(unauthenticated.reason, 'unauthenticated');
    assert.equal(tx.pendingFor('bob').length, 1);

    // 3. Authenticated recipient can ACK.
    const genuine = await request(
      bob,
      'message_delivered',
      payload
    );

    assert.equal(genuine.accepted, true);
    assert.equal(genuine.duplicate, false);
    assert.equal(tx.pendingFor('bob').length, 0);

    // 4. Repeated ACK must be idempotent.
    const repeated = await request(
      bob,
      'message_delivered',
      payload
    );

    assert.equal(repeated.accepted, true);
    assert.equal(repeated.duplicate, true);

    // 5. Revoke server-bound identity.
    const revoked = await request(bob, 'revoke_session', {});
    assert.equal(revoked.revoked, true);

    const afterRevoke = await request(
      bob,
      'message_delivered',
      payload
    );

    assert.equal(afterRevoke.reason, 'unauthenticated');

    // 6. Identity spoofing never recreated pending data.
    assert.equal(tx.pendingFor('bob').length, 0);
  } finally {
    for (const client of clients) client.terminate();
    for (const socket of wss.clients) socket.terminate();

    await new Promise(resolve => wss.close(resolve));
  }
});