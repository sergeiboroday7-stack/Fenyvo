'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createMessageTransaction } =
  require('../server_message_transaction');

const { createMessageDeliveryService } =
  require('../server_message_delivery_service');

function createStore() {
  let records = {};
  let failWrites = false;

  return {
    load: () => structuredClone(records),
    save(next) {
      if (failWrites) throw new Error('simulated disk failure');
      records = structuredClone(next);
    },
    fail(value) {
      failWrites = value;
    },
  };
}

const message = {
  id: 'integration-message-123',
  from: 'alice',
  to: 'bob',
  text: 'hello',
};

function build(store, online = true) {
  const tx = createMessageTransaction({ store });
  const events = [];
  const socket = { readyState: 1 };

  const delivery = createMessageDeliveryService({
    queueMessage(to, item) {
      assert.equal(to, item.to);
      return tx.accept(item);
    },
    getRecipientSocket: () => online ? socket : null,
    isSocketOpen: ws => ws.readyState === 1,
    sendMessage(ws, type, item) {
      events.push(['send', type, item.id]);
    },
    notifyOffline(to, item) {
      events.push(['notify', to, item.id]);
    },
  });

  return { tx, delivery, events };
}

test('new message is persisted before online delivery', () => {
  const store = createStore();
  const { tx, delivery, events } = build(store);

  assert.deepEqual(delivery.deliver(message), {
    queued: true,
    online: true,
  });

  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(events.length, 1);
  assert.equal(events[0][0], 'send');
});

test('identical retry does not send second online event', () => {
  const store = createStore();
  const { tx, delivery, events } = build(store);

  delivery.deliver(message);
  const result = delivery.deliver({ ...message });

  assert.equal(result.duplicate, true);
  assert.equal(events.length, 1);
  assert.equal(tx.pendingFor('bob').length, 1);
});

test('same ID with changed content cannot be delivered', () => {
  const store = createStore();
  const { delivery, events } = build(store);

  delivery.deliver(message);

  const result = delivery.deliver({
    ...message,
    text: 'modified',
  });

  assert.equal(result.conflict, true);
  assert.equal(events.length, 1);
});

test('offline retry creates only one notification', () => {
  const store = createStore();
  const { tx, delivery, events } = build(store, false);

  delivery.deliver(message);
  delivery.deliver(message);

  assert.equal(tx.pendingFor('bob').length, 1);
  assert.equal(
    events.filter(event => event[0] === 'notify').length,
    1
  );
});

test('retry after restart does not create new delivery', () => {
  const store = createStore();

  build(store).delivery.deliver(message);

  const restarted = build(store);
  const result = restarted.delivery.deliver(message);

  assert.equal(result.duplicate, true);
  assert.equal(restarted.events.length, 0);
  assert.equal(restarted.tx.pendingFor('bob').length, 1);
});

test('disk failure prevents acknowledgement and send', () => {
  const store = createStore();
  const { tx, delivery, events } = build(store);

  store.fail(true);

  assert.throws(
    () => delivery.deliver(message),
    /simulated disk failure/
  );

  assert.equal(events.length, 0);
  assert.equal(tx.pendingFor('bob').length, 0);

  store.fail(false);

  assert.equal(delivery.deliver(message).queued, true);
  assert.equal(events.length, 1);
});

test('authenticated recipient can clear pending payload', () => {
  const store = createStore();
  const { tx, delivery } = build(store);

  delivery.deliver(message);

  assert.equal(tx.markDelivered(message, 'bob'), true);
  assert.equal(tx.pendingFor('bob').length, 0);

  assert.equal(delivery.deliver(message).duplicate, true);
});