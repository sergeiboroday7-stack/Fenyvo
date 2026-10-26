'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createPresenceDelivery } =
  require('../server_presence_delivery');

function fixture() {
  const events = [];

  const clients = [
    { user: 'alice', open: true },
    { user: 'mallory', open: true },
    { user: null, open: true },
    { user: 'bob', open: false },
  ];

  const delivery = createPresenceDelivery({
    getClients: () => clients,
    getAuthenticatedUser: client => client.user,
    getVisibleOnlineList: viewer => ({
      users: viewer === 'alice' ? ['bob'] : [],
    }),
    getUserStatusData: username => ({
      username,
      online: true,
      lastSeen: '2026-10-24T12:00:00Z',
    }),
    canViewPresence: (viewer, username) =>
      viewer === 'alice' && username === 'bob',
    isOpen: client => client.open === true,
    send: (client, type, data) => {
      events.push({ recipient: client.user, type, data });
    },
  });

  return { delivery, events };
}

test('online lists are personalized', () => {
  const { delivery, events } = fixture();

  delivery.deliverUserLists();

  assert.deepEqual(events.map(e => ({
    recipient: e.recipient,
    users: e.data.users,
  })), [
    { recipient: 'alice', users: ['bob'] },
    { recipient: 'mallory', users: [] },
  ]);
});

test('unauthenticated clients receive no online list', () => {
  const { delivery, events } = fixture();

  delivery.deliverUserLists();

  assert.equal(events.some(e => e.recipient === null), false);
});

test('status reaches only authorized viewers', () => {
  const { delivery, events } = fixture();

  delivery.deliverUserStatus('bob');

  assert.deepEqual(events.map(e => e.recipient), ['alice']);
  assert.equal(events[0].data.online, true);
});

test('lastSeen never reaches unauthorized viewers', () => {
  const { delivery, events } = fixture();

  delivery.deliverUserStatus('bob');

  assert.equal(
    events.some(e => e.recipient === 'mallory'),
    false
  );
});

test('direct status request respects access control', () => {
  const { delivery } = fixture();

  assert.equal(
    delivery.getStatusForViewer('mallory', 'bob'),
    null
  );

  assert.equal(
    delivery.getStatusForViewer('alice', 'bob').username,
    'bob'
  );
});

test('invalid identities expose no status', () => {
  const { delivery, events } = fixture();

  delivery.deliverUserStatus('');

  assert.equal(delivery.getStatusForViewer('', 'bob'), null);
  assert.equal(delivery.getStatusForViewer('alice', ''), null);
  assert.equal(events.length, 0);
});

test('closed sockets receive no events', () => {
  const { delivery, events } = fixture();

  delivery.deliverUserLists();
  delivery.deliverUserStatus('bob');

  assert.equal(events.some(e => e.recipient === 'bob'), false);
});

test('missing dependencies fail closed', () => {
  assert.throws(
    () => createPresenceDelivery({}),
    TypeError
  );
});