'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

const start = source.indexOf("type ===\n");
const routeMatch = source.match(
  /if\s*\(\s*type\s*===\s*'get_users'\s*\)\s*\{[\s\S]*?(?=\/\/\s*GET USER STATUS)/
);

assert.ok(routeMatch, 'get_users handler not found');

const route = routeMatch[0];

test('get_users requires authenticated WebSocket identity', () => {
  assert.match(
    route,
    /wsSessionIdentity\.getAuthenticatedUser\(ws\)\s*!==\s*currentUser/
  );
});

test('get_users rejects replaced and revoked sessions', () => {
  assert.match(
    route,
    /!currentUser/
  );
  assert.match(
    route,
    /onlineUsers\.get\(currentUser\)\s*!==\s*ws/
  );
});

test('get_users validates session before returning contacts', () => {
  const auth = route.indexOf(
    'wsSessionIdentity.getAuthenticatedUser(ws)'
  );
  const contacts = route.indexOf(
    'presenceProtocol.getContactList(currentUser)'
  );
  const online = route.indexOf(
    'presenceProtocol.getVisibleOnlineList(currentUser)'
  );

  assert.ok(auth >= 0);
  assert.ok(contacts > auth);
  assert.ok(online > auth);
  assert.match(
    route,
    /send\(ws,\s*'contact_list',\s*contactList\)/
  );
  assert.match(
    route,
    /send\(ws,\s*'users',\s*\{[\s\S]*\.\.\.onlineList,[\s\S]*presence_authoritative:\s*true,[\s\S]*\}\)/
  );
});
