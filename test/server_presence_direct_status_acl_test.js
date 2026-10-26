'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

const match = source.match(
  /if\s*\(\s*type\s*===\s*'get_user_status'\s*\)\s*\{[\s\S]*?(?=\/\/\s*TRUST SERVER ENFORCEMENT)/
);

assert.ok(match, 'Status route must exist');

const route = match[0];

test('direct status checks authenticated session', () => {
  assert.match(
    route,
    /wsSessionIdentity\.getAuthenticatedUser\(ws\)\s*===\s*currentUser/
  );
  assert.match(
    route,
    /onlineUsers\.get\(currentUser\)\s*===\s*ws/
  );
});

test('direct status uses private delivery ACL', () => {
  assert.match(
    route,
    /presenceDelivery\.getStatusForViewer\(\s*verifiedViewer,\s*username\s*\)/
  );
});

test('direct status no longer bypasses privacy ACL', () => {
  assert.doesNotMatch(route, /getUserStatusData\s*\(/);
});

test('direct status still rejects missing or denied status', () => {
  assert.match(route, /if\s*\(!status\)/);
});