'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageDeliveryService } =
  require('../server_message_delivery_service');

const message = {
  id: 'delivery-module-123',
  from: 'alice',
  to: 'bob',
  text: 'hello',
};

function setup({ online = false, failQueue = false } = {}) {
  const events = [];
  const socket = { readyState: online ? 1 : 3 };

  const service = createMessageDeliveryService({
    queueMessage(to, data) {
      if (failQueue) throw new Error('storage failure');
      events.push(['queue', to, data.id]);
    },
    getRecipientSocket: () => online ? socket : null,
    isSocketOpen: ws => ws.readyState === 1,
    sendMessage(ws, type, data) {
      events.push(['send', type, data.id]);
    },
    notifyOffline(to, data) {
      events.push(['notify', to, data.id]);
    },
  });

  return { service, events };
}

test('online delivery queues before sending', () => {
  const { service, events } = setup({ online: true });

  const result = service.deliver(message);

  assert.deepEqual(result, { queued: true, online: true });
  assert.deepEqual(
    events.map(event => event[0]),
    ['queue', 'send']
  );
});

test('offline delivery queues and notifies', () => {
  const { service, events } = setup();

  const result = service.deliver(message);

  assert.deepEqual(result, { queued: true, online: false });
  assert.deepEqual(
    events.map(event => event[0]),
    ['queue', 'notify']
  );
});

test('queue failure prevents sending and notification', () => {
  const { service, events } = setup({
    online: true,
    failQueue: true,
  });

  assert.throws(
    () => service.deliver(message),
    /storage failure/
  );

  assert.deepEqual(events, []);
});

test('invalid recipient is rejected', () => {
  const { service, events } = setup();

  assert.throws(
    () => service.deliver({ ...message, to: '' }),
    TypeError
  );

  assert.deepEqual(events, []);
});

test('missing dependencies are rejected', () => {
  assert.throws(
    () => createMessageDeliveryService({}),
    TypeError
  );
});