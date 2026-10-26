'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

function section(start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a);

  assert.ok(a >= 0 && b > a);
  return source.slice(a, b);
}

const users = section(
  'function broadcastUsers()',
  '// STATUS'
);

const status = section(
  'function broadcastUserStatus(',
  '// USERNAME'
);

test('online lists use private delivery', () => {
  assert.match(
    users,
    /presenceDelivery\.deliverUserLists\(\)/
  );
});

test('online lists never use global broadcast', () => {
  assert.doesNotMatch(
    users,
    /\bbroadcast\s*\(\s*['"]users['"]/
  );
});

test('individual status uses private delivery', () => {
  assert.match(
    status,
    /presenceDelivery\.deliverUserStatus\(username\)/
  );
});

test('individual status never uses global broadcast', () => {
  assert.doesNotMatch(
    status,
    /\bbroadcast\s*\(\s*['"]user_status['"]/
  );
});

test('private delivery uses server-bound identities', () => {
  assert.match(
    source,
    /wsSessionIdentity\.getAuthenticatedUser\(client\)/
  );

  assert.match(
    source,
    /onlineUsers\.get\(viewer\)\s*===\s*client/
  );
});

test('direct status remains protected', () => {
  assert.match(
    source,
    /presenceDelivery\.getStatusForViewer\(\s*verifiedViewer,\s*username\s*\)/
  );
});