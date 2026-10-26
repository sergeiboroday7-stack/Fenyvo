'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const WebSocket = require('ws');
const { WebSocketServer } = require('ws');

const { createMessageTransaction } =
  require('../server_message_transaction');

const { createMessageDeliveryService } =
  require('../server_message_delivery_service');

function createStore() {
  let saved = {};

  return {
    load: () => structuredClone(saved),
    save: next => { saved = structuredClone(next); },
  };
}

const makeMessage = id => ({
  id,
  from: 'alice',
  to: 'bob',
  text: 'WebSocket integration test',
});

test('local WebSocket delivery, reconnect, replay and ACK', {
  timeout: 15000,
}, async () => {
  const store = createStore();
  const tx = createMessageTransaction({ store });

  const wss = new WebSocketServer({
    host: '127.0.0.1',
    port: 0,
  });

  const clients = new Set();
  let activeSocket = null;
  let offlineNotifications = 0;

  wss.on('connection', socket => {
    activeSocket = socket;

    socket.on('close', () => {
      if (activeSocket === socket) activeSocket = null;
    });
  });

  const service = createMessageDeliveryService({
    queueMessage(to, item) {
      assert.equal(to, 'bob');
      return tx.accept(item);
    },
    getRecipientSocket: recipient =>
      recipient === 'bob' ? activeSocket : null,
    isSocketOpen: socket =>
      socket.readyState === WebSocket.OPEN,
    sendMessage(socket, type, item) {
      socket.send(JSON.stringify({ type, data: item }));
    },
    notifyOffline() {
      offlineNotifications++;
    },
    pendingFor: recipient => tx.pendingFor(recipient),
  });

  async function connect(port) {
    const client = new WebSocket(`ws://127.0.0.1:${port}`);
    clients.add(client);
    await once(client, 'open');
    return client;
  }

  try {
    if (!wss.address()) await once(wss, 'listening');

    const port = wss.address().port;

    const firstClient = await connect(port);
    const firstFrame = once(firstClient, 'message');

    const first = makeMessage('ws-first-123');

    assert.equal(service.deliver(first).online, true);

    const [raw] = await firstFrame;
    assert.equal(JSON.parse(raw.toString()).data.id, first.id);
    assert.equal(tx.pendingFor('bob').length, 1);

    const closed = once(firstClient, 'close');
    firstClient.close();
    await closed;

    activeSocket = null;

    const second = makeMessage('ws-second-123');

    assert.equal(service.deliver(second).online, false);
    assert.equal(offlineNotifications, 1);
    assert.equal(tx.pendingFor('bob').length, 2);

    const secondClient = await connect(port);
    const frames = [];

    const received = new Promise(resolve => {
      secondClient.on('message', data => {
        frames.push(JSON.parse(data.toString()));

        if (frames.length === 2) resolve();
      });
    });

    assert.equal(service.redeliverPending('bob'), 2);
    await received;

    assert.deepEqual(
      frames.map(frame => frame.data.id).sort(),
      [first.id, second.id].sort()
    );

    assert.equal(tx.markDelivered(first, 'bob'), true);
    assert.equal(tx.markDelivered(second, 'bob'), true);

    assert.equal(tx.pendingFor('bob').length, 0);
    assert.equal(service.redeliverPending('bob'), 0);
    assert.equal(service.deliver(first).duplicate, true);
  } finally {
    for (const client of clients) client.terminate();
    for (const socket of wss.clients) socket.terminate();

    await new Promise(resolve => wss.close(resolve));
  }
});