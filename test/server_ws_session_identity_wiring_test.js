'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

test('server imports session identity module', () => {
  assert.match(
    source,
    /require\('\.\/server_ws_session_identity'\)/
  );
});

test('server creates one identity registry', () => {
  assert.match(
    source,
    /const wsSessionIdentity = createServerSessionIdentity\(\)/
  );
});

test('identity binding follows password verification', () => {
  const passwordCheck = source.indexOf('!passwordCorrect');
  const binding = source.indexOf(
    'wsSessionIdentity.bindAuthenticated(ws, username)'
  );

  assert.ok(passwordCheck >= 0);
  assert.ok(binding > passwordCheck);
});

test('account switching on one socket is blocked', () => {
  assert.match(
    source,
    /boundUser && boundUser !== username/
  );
});

test('session identity is revoked on close', () => {
  const closeHandler = source.indexOf("'close',");
  const revoke = source.indexOf(
    'wsSessionIdentity.revoke(ws)',
    closeHandler
  );

  assert.ok(closeHandler >= 0);
  assert.ok(revoke > closeHandler);
});

test('frame guard state is cleaned on close', () => {
  assert.match(source, /wsFrameGuard\.revoke\(ws\)/);
});

test('old socket cannot remove newer online session', () => {
  assert.match(
    source,
    /onlineUsers\.get\(\s*currentUser,\s*\)\s*=== ws/
  );
});