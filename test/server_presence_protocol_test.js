'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createPresenceProtocol,
  normalizeUsernames,
} = require('../server_presence_protocol');

function fixture() {
  const online = new Set(['bob']);

  const protocol = createPresenceProtocol({
    getAcceptedContacts: viewer =>
      viewer === 'alice' ? ['bob', 'charlie'] : [],
    isOnline: username => online.has(username),
    canViewPresence: (viewer, username) =>
      viewer === 'alice' && username !== 'charlie',
  });

  return { protocol, online };
}

test('contacts include offline users', () => {
  const { protocol } = fixture();

  assert.deepEqual(
    protocol.getContactList('alice'),
    { contacts: ['bob', 'charlie'] }
  );
});

test('online contains only active visible contacts', () => {
  const { protocol } = fixture();

  assert.deepEqual(
    protocol.getVisibleOnlineList('alice'),
    { users: ['bob'] }
  );
});

test('going offline does not remove contacts', () => {
  const { protocol, online } = fixture();

  online.clear();

  assert.deepEqual(
    protocol.getContactList('alice'),
    { contacts: ['bob', 'charlie'] }
  );

  assert.deepEqual(
    protocol.getVisibleOnlineList('alice'),
    { users: [] }
  );
});

test('privacy denies unauthorized presence', () => {
  const protocol = createPresenceProtocol({
    getAcceptedContacts: () => ['bob'],
    isOnline: () => true,
    canViewPresence: () => false,
  });

  assert.deepEqual(
    protocol.getVisibleOnlineList('alice'),
    { users: [] }
  );
});

test('empty viewer exposes no data', () => {
  const { protocol } = fixture();

  assert.deepEqual(protocol.getContactList(''), { contacts: [] });
  assert.deepEqual(protocol.getVisibleOnlineList(''), { users: [] });
});

test('duplicate usernames are normalized', () => {
  assert.deepEqual(
    normalizeUsernames(['bob', 'BOB', 'charlie', '', ' bob ']),
    ['bob', 'charlie']
  );
});

test('missing dependencies are rejected', () => {
  assert.throws(() => createPresenceProtocol({}), TypeError);
});