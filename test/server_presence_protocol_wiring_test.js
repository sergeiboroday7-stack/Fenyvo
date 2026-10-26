'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

test('server imports separate presence protocol', () => {
  assert.match(
    source,
    /require\('\.\/server_presence_protocol'\)/
  );
});

test('protocol is initialized with independent dependencies', () => {
  assert.match(
    source,
    /const presenceProtocol = createPresenceProtocol\(\{/
  );

  assert.match(
    source,
    /getAcceptedContacts: getAcceptedCommunicationContacts/
  );

  assert.match(
    source,
    /isOnline: \(username\) => publicPresence\.isOnline\(username\)/
  );

  assert.match(
    source,
    /canViewPresence: \(viewer, username\)/
  );
});