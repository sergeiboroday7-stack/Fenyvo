'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

test('private delivery module is imported', () => {
  assert.match(
    source,
    /require\('\.\/server_presence_delivery'\)/
  );
});

test('private delivery uses server-bound identity', () => {
  assert.match(
    source,
    /wsSessionIdentity\.getAuthenticatedUser\(client\)/
  );

  assert.match(
    source,
    /onlineUsers\.get\(viewer\) === client/
  );
});

test('private delivery checks mutual contacts', () => {
  assert.match(
    source,
    /const presenceDelivery = createPresenceDelivery\(\{/
  );

  assert.match(
    source,
    /presenceProtocol\.getContactList\(viewer\)/
  );

  assert.match(
    source,
    /presenceProtocol\.getContactList\(username\)/
  );

  assert.match(
    source,
    /client\.readyState === WebSocket\.OPEN/
  );
});