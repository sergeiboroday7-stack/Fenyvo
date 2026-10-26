'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const { createMessageDeliveryService } =
  require('../server_message_delivery_service');

const message = {
  id: 'reconnect-message-123',
  from: 'alice',
  to: 'bob',
  text: 'hello',
};

function createStore() {
  let data = {};

  return {
    load: () => structuredClone(data),
    save: next => { data = structuredClone(next); },
    snapshot: () => structuredClone(data),
  };
}

function setup(store, isOnline = true) {
  const tx = createMessageTransaction({ store });
  const events = [];
  const socket = { readyState: isOnline ? 1 : 3 };

  const service = createMessageDeliveryService({
    queueMessage: (to, item) => tx.accept(item),
    getRecipientSocket: () => socket,
    isSocketOpen: ws => ws.readyState === 1,
    sendMessage: (ws, type, item) => {
      events.push([type, item.id]);
    },
    pendingFor: recipient => tx.pendingFor(recipient),
  });

  return { tx, service, events, socket };
}

test('accepted message can be resent after reconnect', () => {
  const store = createStore();
  const env = setup(store);

  env.service.deliver(message);
  assert.equal(env.events.length, 1);

  assert.equal(env.service.redeliverPending('bob'), 1);
  assert.equal(env.events.length, 2);
  assert.equal(env.tx.pendingFor('bob').length, 1);
  assert.equal(Object.keys(store.snapshot()).length, 1);
});

test('disconnected recipient receives no replay', () => {
  const env = setup(createStore(), false);

  env.service.deliver(message);

  assert.equal(env.service.redeliverPending('bob'), 0);
  assert.equal(env.events.length, 0);
  assert.equal(env.tx.pendingFor('bob').length, 1);
});

test('acknowledgement prevents future replay', () => {
  const env = setup(createStore());

  env.service.deliver(message);
  env.tx.markDelivered(message, 'bob');

  assert.equal(env.service.redeliverPending('bob'), 0);
  assert.equal(env.events.length, 1);
  assert.equal(env.tx.pendingFor('bob').length, 0);
});

test('pending message survives restart and replays', () => {
  const store = createStore();

  setup(store, false).service.deliver(message);

  const restarted = setup(store);

  assert.equal(restarted.service.redeliverPending('bob'), 1);
  assert.equal(restarted.events.length, 1);
  assert.equal(restarted.tx.pendingFor('bob').length, 1);
});

test('other recipient cannot receive bob pending messages', () => {
  const env = setup(createStore());

  env.service.deliver(message);

  assert.equal(env.service.redeliverPending('charlie'), 0);
  assert.equal(env.events.length, 1);
});

test('missing authenticated identity is rejected', () => {
  const env = setup(createStore());

  assert.throws(
    () => env.service.redeliverPending(''),
    TypeError
  );
});

test('replay requires configured pending source', () => {
  const env = setup(createStore());

  const service = createMessageDeliveryService({
    queueMessage: () => {},
    getRecipientSocket: () => env.socket,
    isSocketOpen: ws => ws.readyState === 1,
    sendMessage: () => {},
  });

  assert.throws(
    () => service.redeliverPending('bob'),
    /not configured/
  );
});