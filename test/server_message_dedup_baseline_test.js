'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

// Model of the currently observed server message handling.
// This is NOT an integration test of server.js.
function createBaseline() {
  const queues = new Map();
  const deliveries = [];

  function queueOfflineMessage(to, message) {
    const queue = queues.get(to) || [];

    if (!queue.some(item => item.id === message.id)) {
      queue.push(message);
    }

    queues.set(to, queue);
  }

  function receiveMessage(to, message) {
    queueOfflineMessage(to, message);

    // Current main handler sends the message to an online receiver
    // independently of whether the queue already contains the ID.
    deliveries.push({ to, id: message.id });
  }

  function acknowledgeDelivery(to, id) {
    const queue = queues.get(to) || [];
    queues.set(to, queue.filter(item => item.id !== id));
  }

  return {
    receiveMessage,
    acknowledgeDelivery,
    deliveries,
    queues,
  };
}

test('baseline: repeated message ID stays unique in offline queue', () => {
  const server = createBaseline();
  const msg = { id: '1234567890123456-abcdef0123456789' };

  server.receiveMessage('receiver', msg);
  server.receiveMessage('receiver', msg);

  assert.equal(server.queues.get('receiver').length, 1);
});

test('baseline: repeated message ID can be delivered twice', () => {
  const server = createBaseline();
  const msg = { id: '1234567890123456-abcdef0123456789' };

  server.receiveMessage('receiver', msg);
  server.receiveMessage('receiver', msg);

  assert.equal(server.deliveries.length, 2);
});

test('baseline: retry after acknowledgement can be delivered again', () => {
  const server = createBaseline();
  const msg = { id: '1234567890123456-abcdef0123456789' };

  server.receiveMessage('receiver', msg);
  server.acknowledgeDelivery('receiver', msg.id);
  server.receiveMessage('receiver', msg);

  assert.equal(server.deliveries.length, 2);
});