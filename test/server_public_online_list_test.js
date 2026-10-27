'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const { createPresenceDelivery } =
  require('../server_presence_delivery');

const { createPresenceProtocol } =
  require('../server_presence_protocol');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

const start = source.indexOf('function broadcastUsers(');
const end = source.indexOf('function getUserStatusData(', start);

assert.ok(start >= 0 && end > start);

const section = source.slice(start, end);

function createHarness(aliceActive) {
  const events = [];

  const sockets = [
    { user: 'alice', open: true },
    { user: 'bob', open: true },
    { user: 'mallory', open: true },
    { user: null, open: true },
  ];

  const onlineUsers = new Map([
    ['alice', sockets[0]],
    ['bob', sockets[1]],
    ['mallory', sockets[2]],
  ]);

  const accepted = {
    alice: ['bob'],
    bob: ['alice'],
    mallory: [],
  };

  const getContacts = user => accepted[user] || [];

  const publicPresence = {
    isOnline: user => user === 'alice' && aliceActive,
  };

  const protocol = createPresenceProtocol({
    getAcceptedContacts: getContacts,
    isOnline: user => publicPresence.isOnline(user),
    canViewPresence: (viewer, subject) =>
      getContacts(subject).includes(viewer),
  });

  const delivery = createPresenceDelivery({
    getClients: () => sockets,
    getAuthenticatedUser: socket => {
      const user = socket.user;
      return user && onlineUsers.get(user) === socket
        ? user
        : null;
    },
    getVisibleOnlineList: viewer =>
      protocol.getVisibleOnlineList(viewer),
    getUserStatusData: () => null,
    canViewPresence: (viewer, subject) =>
      getContacts(viewer).includes(subject) &&
      getContacts(subject).includes(viewer),
    isOpen: socket => socket.open,
    send: (socket, type, data) => {
      events.push({
        recipient: socket.user,
        type,
        users: [...data.users],
        authoritative: data.presence_authoritative === true,
      });
    },
  });

  const sandbox = {
    onlineUsers,
    publicPresence,
    lastPublicPresence: new Map(),
    presenceDelivery: delivery,
    console: { log() {} },
    broadcast() {
      throw new Error('Global presence broadcast is forbidden');
    },
  };

  vm.createContext(sandbox);
  vm.runInContext(section, sandbox);

  return { sandbox, events, onlineUsers };
}

test('public list filters transport sockets by foreground presence', () => {
  assert.match(
    section,
    /onlineUsers\.keys\(\)/
  );

  assert.match(
    section,
    /\.filter\(\(username\) => publicPresence\.isOnline\(username\)\)/
  );

  assert.match(
    section,
    /presenceDelivery\.deliverUserLists\(\)/
  );
});

test('background socket is not shown as online', () => {
  const h = createHarness(true);
  h.sandbox.broadcastUsers();

  const bob = h.events.find(e => e.recipient === 'bob');
  const alice = h.events.find(e => e.recipient === 'alice');
  const mallory = h.events.find(e => e.recipient === 'mallory');

  assert.deepEqual(bob.users, ['alice']);
  assert.deepEqual(alice.users, []);
  assert.deepEqual(mallory.users, []);

  assert.equal(bob.authoritative, true);
  assert.equal(alice.authoritative, true);
  assert.equal(mallory.authoritative, true);

  assert.equal(
    h.events.some(e => e.recipient === null),
    false
  );
});

test('all-background users produce empty public online list', () => {
  const h = createHarness(false);
  h.sandbox.broadcastUsers();

  assert.ok(h.events.length > 0);

  for (const event of h.events) {
    assert.deepEqual(event.users, []);
  }

  assert.equal(h.onlineUsers.size, 3);
});

test('presence changes broadcast individual and list updates', () => {
  const start = source.indexOf("if (type === 'presence_update')");
  const end = source.indexOf("'get_user_status'", start);

  assert.ok(start >= 0 && end > start);

  const handler = source.slice(start, end);

  assert.match(
    handler,
    /if \(wasOnline !== isOnline\) \{\s*broadcastUserStatus\(currentUser\);\s*broadcastUsers\(\);/
  );
});

test('socket transport map is preserved', () => {
  assert.match(
    source,
    /onlineUsers\.set\(\s*username,\s*ws,\s*\)/
  );

  assert.match(
    source,
    /onlineUsers\.get\(\s*username,\s*\)/
  );
});
