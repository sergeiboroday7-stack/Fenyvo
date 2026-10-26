'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const WebSocket = require('ws');
const { WebSocketServer } = require('ws');
const { createPresenceDelivery } =
  require('../server_presence_delivery');
const { createPresenceProtocol } =
  require('../server_presence_protocol');

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function waitFor(check) {
  for (let i = 0; i < 200; i++) {
    if (check()) return;
    await sleep(10);
  }
  assert.fail('Timed out waiting for a NEW WebSocket event');
}

test('real WebSocket presence privacy and lifecycle', {
  timeout: 15000,
}, async () => {
  const wss = new WebSocketServer({
    host: '127.0.0.1',
    port: 0,
  });

  const clients = [];
  const identities = new WeakMap();
  const activeSockets = new Map();
  const inbox = new Map();
  const foreground = new Set(['alice']);

  const contacts = {
    alice: ['bob'],
    bob: ['alice'],
    mallory: [],
  };

  const accepted = user => contacts[user] || [];

  const protocol = createPresenceProtocol({
    getAcceptedContacts: accepted,
    isOnline: user => foreground.has(user),
    canViewPresence: (viewer, subject) =>
      accepted(subject).includes(viewer),
  });

  const delivery = createPresenceDelivery({
    getClients: () => wss.clients,

    getAuthenticatedUser: socket => {
      const username = identities.get(socket);
      return username && activeSockets.get(username) === socket
        ? username
        : null;
    },

    getVisibleOnlineList: viewer =>
      protocol.getVisibleOnlineList(viewer),

    getUserStatusData: username => ({
      username,
      online: foreground.has(username),
      lastSeen: 'TEST_LAST_SEEN',
    }),

    canViewPresence: (viewer, subject) =>
      viewer === subject ||
      (
        accepted(viewer).includes(subject) &&
        accepted(subject).includes(viewer)
      ),

    isOpen: socket =>
      socket.readyState === WebSocket.OPEN,

    send: (socket, type, data) =>
      socket.send(JSON.stringify({ type, data })),
  });

  async function connect(label, username = null) {
    const incoming = once(wss, 'connection');
    const client = new WebSocket(
      `ws://127.0.0.1:${wss.address().port}`
    );

    const received = [];
    inbox.set(label, received);

    client.on('message', message => {
      received.push(JSON.parse(message.toString()));
    });

    clients.push(client);

    const [socket] = await incoming;
    await once(client, 'open');

    if (username) {
      identities.set(socket, username);
      activeSockets.set(username, socket);
    }

    return socket;
  }

  const events = (label, type) =>
    inbox.get(label).filter(e => e.type === type);

  try {
    if (!wss.address()) {
      await once(wss, 'listening');
    }

    const oldAlice = await connect('alice', 'alice');
    await connect('bob', 'bob');
    await connect('mallory', 'mallory');
    await connect('guest');

    delivery.deliverUserLists();

    await waitFor(() =>
      events('alice', 'users').length === 1 &&
      events('bob', 'users').length === 1 &&
      events('mallory', 'users').length === 1
    );

    assert.deepEqual(
      events('bob', 'users')[0].data.users,
      ['alice']
    );

    assert.deepEqual(
      events('alice', 'users')[0].data.users,
      []
    );

    assert.deepEqual(
      events('mallory', 'users')[0].data.users,
      []
    );

    assert.equal(events('guest', 'users').length, 0);

    delivery.deliverUserStatus('alice');

    await waitFor(() =>
      events('bob', 'user_status').length === 1
    );

    assert.equal(
      events('bob', 'user_status')[0].data.lastSeen,
      'TEST_LAST_SEEN'
    );

    assert.equal(events('guest', 'user_status').length, 0);
    assert.equal(events('mallory', 'user_status').length, 0);

    assert.equal(
      delivery.getStatusForViewer('mallory', 'alice'),
      null
    );

    assert.equal(
      delivery.getStatusForViewer('bob', 'alice').online,
      true
    );

    const newAlice = await connect('alice_new', 'alice');
    assert.notEqual(newAlice, oldAlice);

    const oldAliceCount = events('alice', 'users').length;

    delivery.deliverUserLists();

    await waitFor(() =>
      events('alice_new', 'users').length === 1
    );

    await sleep(30);

    assert.equal(
      events('alice', 'users').length,
      oldAliceCount
    );

    activeSockets.delete('alice');

    const revokedCount = events('alice_new', 'users').length;

    delivery.deliverUserLists();

    await sleep(30);

    assert.equal(
      events('alice_new', 'users').length,
      revokedCount
    );

    // Key fix: record the count BEFORE changing presence.
    const bobBeforeOffline = events('bob', 'users').length;

    foreground.clear();
    delivery.deliverUserLists();

    // Wait for the NEW event, not an old accumulated event.
    await waitFor(() =>
      events('bob', 'users').length > bobBeforeOffline
    );

    const latestBobEvent = events('bob', 'users').at(-1);

    assert.deepEqual(latestBobEvent.data.users, []);
    assert.equal(activeSockets.has('bob'), true);

    assert.equal(events('guest', 'users').length, 0);
    assert.equal(events('guest', 'user_status').length, 0);

    console.log('REAL_WS_PRIVATE_PRESENCE_PASS');
  } finally {
    for (const client of clients) client.terminate();
    for (const socket of wss.clients) socket.terminate();

    await new Promise((resolve, reject) => {
      wss.close(error =>
        error ? reject(error) : resolve()
      );
    });
  }
});