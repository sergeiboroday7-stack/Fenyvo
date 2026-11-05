'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { once } = require('node:events');
const WebSocket = require('ws');
const { WebSocketServer } = WebSocket;

const { createMessageDeliveryService } =
  require('../server_message_delivery_service');

const source = fs.readFileSync(
  require('node:path').join(__dirname, '..', 'server.js'), 'utf8'
);

const definitions = [
  {
    kind: 'e2ee',
    start: 'const deliveryResult = messageDeliveryService.deliver(messageData, { senderSocket: ws });',
  },
  {
    kind: 'media',
    start: 'const mediaDeliveryResult = messageDeliveryService.deliver(messageData, { senderSocket: ws });',
  },
  {
    kind: 'ordinary',
    start: 'const ordinaryDeliveryResult = messageDeliveryService.deliver(messageData, { senderSocket: ws });',
  },
];

const ackPattern =
  /send\(\s*ws,\s*'message_sent',\s*messageData,?\s*\);/;

function extract(definition) {
  const start = source.indexOf(definition.start);
  assert.ok(start >= 0, `${definition.kind}: delivery call missing`);

  assert.equal(
    source.indexOf(definition.start, start + 1),
    -1,
    `${definition.kind}: duplicate call site`
  );

  const remaining = source.slice(start);
  const ack = ackPattern.exec(remaining);

  assert.ok(
    ack && ack.index < 7000,
    `${definition.kind}: ACK not found`
  );

  const code = remaining.slice(0, ack.index + ack[0].length);

  assert.doesNotMatch(
    code,
    /queueOfflineMessage\s*\(/,
    `${definition.kind}: legacy queue call remains`
  );

  assert.match(code, /sendFcmPush\s*\(/);

  return new Function(
    'messageDeliveryService',
    'messageData',
    'sendFcmPush',
    'send',
    'ws',
    'to',
    'currentUser',
    'text',
    'console',
    code
  );
}

for (const definition of definitions) {
  const handler = extract(definition);

  test(`${definition.kind}: real WebSocket online and offline`, {
    timeout: 12000,
  }, async () => {
    const wss = new WebSocketServer({
      host: '127.0.0.1',
      port: 0,
    });

    const clients = [];
    let recipientSocket = null;
    const events = [];
    let queueCalls = 0;
    let pushCalls = 0;

    wss.on('connection', socket => {
      recipientSocket = socket;
      socket.on('close', () => {
        if (recipientSocket === socket) recipientSocket = null;
      });
    });

    try {
      if (!wss.address()) await once(wss, 'listening');

      const port = wss.address().port;
      const recipient = new WebSocket(`ws://127.0.0.1:${port}`);
      clients.push(recipient);
      await once(recipient, 'open');

      const service = createMessageDeliveryService({
        queueMessage(user, item) {
          assert.equal(user, 'bob');
          assert.equal(item.to, 'bob');
          events.push('persist');
          queueCalls++;
        },
        getRecipientSocket(user) {
          assert.equal(user, 'bob');
          return recipientSocket;
        },
        isSocketOpen(socket) {
          return socket.readyState === WebSocket.OPEN;
        },
        sendMessage(socket, type, item) {
          events.push('deliver');
          socket.send(JSON.stringify({ type, data: item }));
        },
        notifyOffline() {},
      });

      const senderFrames = [];
      const senderSocket = { readyState: WebSocket.OPEN };

      function send(socket, type, data) {
        assert.equal(socket, senderSocket);
        senderFrames.push({ type, data });
        events.push('ack');
      }

      function sendFcmPush(payload) {
        assert.equal(payload.username, 'bob');
        pushCalls++;
        events.push('push');
        return Promise.resolve(true);
      }

      const log = { log() {}, warn() {}, error() {} };

      const onlineMessage = {
        id: `${definition.kind}-online-1`,
        from: 'alice',
        to: 'bob',
        text: 'test payload',
        encrypted: definition.kind === 'e2ee',
      };

      const framePromise = once(recipient, 'message');

      handler(
        service, onlineMessage, sendFcmPush, send,
        senderSocket, 'bob', 'alice', onlineMessage.text, log
      );

      const [rawFrame] = await framePromise;
      const frame = JSON.parse(rawFrame.toString());

      assert.equal(frame.type, 'message');
      assert.equal(frame.data.id, onlineMessage.id);
      assert.deepEqual(events, ['persist', 'deliver', 'ack']);
      assert.equal(senderFrames.length, 1);
      assert.equal(senderFrames[0].type, 'message_sent');
      assert.equal(queueCalls, 1);
      assert.equal(pushCalls, 0);

      console.log(`${definition.kind.toUpperCase()}_ONLINE_WS_PASS`);

      const closed = once(recipient, 'close');
      recipient.close();
      await closed;
      recipientSocket = null;

      events.length = 0;

      const offlineMessage = {
        ...onlineMessage,
        id: `${definition.kind}-offline-1`,
      };

      handler(
        service, offlineMessage, sendFcmPush, send,
        senderSocket, 'bob', 'alice', offlineMessage.text, log
      );

      assert.deepEqual(events, ['persist', 'push', 'ack']);
      assert.equal(queueCalls, 2);
      assert.equal(pushCalls, 1);
      assert.equal(senderFrames.length, 2);
      assert.equal(senderFrames[1].type, 'message_sent');

      console.log(`${definition.kind.toUpperCase()}_OFFLINE_WS_PASS`);
    } finally {
      for (const client of clients) client.terminate();
      for (const socket of wss.clients) socket.terminate();

      await new Promise(resolve => wss.close(resolve));
    }
  });
}