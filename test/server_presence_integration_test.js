'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

test('presence module imported and initialized', () => {
  assert.match(
    source,
    /require\('\.\/server_presence_state'\)/
  );
  assert.match(
    source,
    /const publicPresence = createPresenceState/
  );
});

test('login keeps onlineUsers registration and binds presence', () => {
  assert.match(
    source,
    /onlineUsers\.set\(\s*username,\s*ws,\s*\);[\s\S]*?publicPresence\.bind\(ws, username\)/
  );
  assert.doesNotMatch(source, /^\s*\$1\s*$/m);
});

test('public online status uses presence engine', () => {
  const start = source.indexOf('function getUserStatusData(');
  const end = source.indexOf('function broadcastUserStatus(', start);

  assert.ok(start >= 0 && end > start);

  const section = source.slice(start, end);

  assert.match(
    section,
    /online:\s*publicPresence\.isOnline\(username\)/
  );

  assert.doesNotMatch(section, /onlineUsers\.has/);
});

test('presence update validates current authenticated socket', () => {
  const start = source.indexOf("if (type === 'presence_update')");
  const end = source.indexOf("'get_user_status'", start);

  assert.ok(start >= 0 && end > start);

  const section = source.slice(start, end);

  assert.match(section, /onlineUsers\.get\(currentUser\) !== ws/);
  assert.match(
    section,
    /wsSessionIdentity\.getAuthenticatedUser\(ws\) !== currentUser/
  );
  assert.match(section, /typeof data\?\.foreground !== 'boolean'/);
  assert.match(section, /publicPresence\.update\(ws, data\.foreground\)/);
});

test('presence disconnect happens before identity revocation', () => {
  const start = source.search(/ws\.on\(\s*'close'/);
  assert.ok(start >= 0);

  const section = source.slice(start, start + 1000);
  const clear = section.indexOf('publicPresence.disconnect(ws)');
  const revoke = section.indexOf('wsSessionIdentity.revoke(ws)');

  assert.ok(clear >= 0);
  assert.ok(revoke > clear);
});

test('status returns offline unless presence reports foreground', () => {
  const start = source.indexOf('function getUserStatusData(');
  const end = source.indexOf('function broadcastUserStatus(', start);

  let foreground = false;

  const sandbox = {
    registeredUsers: {
      alice: { lastSeen: null },
    },
    publicPresence: {
      isOnline: () => foreground,
    },
  };

  vm.createContext(sandbox);
  vm.runInContext(source.slice(start, end), sandbox);

  assert.equal(sandbox.getUserStatusData('alice').online, false);

  foreground = true;

  assert.equal(sandbox.getUserStatusData('alice').online, true);
  assert.equal(sandbox.getUserStatusData('missing'), null);
});