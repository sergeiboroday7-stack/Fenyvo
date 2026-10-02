'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const server = fs.readFileSync(path.join(root, 'server.js'), 'utf8');
const auth = fs.readFileSync(
  path.join(root, 'lib', 'screens', 'auth_screen.dart'),
  'utf8',
);
const socket = fs.readFileSync(
  path.join(root, 'lib', 'services', 'socket_service.dart'),
  'utf8',
);

assert.match(server, /const LEGAL_TERMS_VERSION = '2026-10-01'/);
assert.match(server, /const LEGAL_PRIVACY_VERSION = '2026-10-01'/);
assert.match(server, /const LEGAL_MINIMUM_AGE = 16/);
assert.match(server, /legalRequired/);
assert.match(server, /type === 'accept_legal'/);
assert.match(server, /acceptedAt: new Date\(\)\.toISOString\(\)/);
assert.match(server, /send\(ws, 'legal_acceptance_success'/);

assert.match(auth, /data\['legalRequired'\] == true/);
assert.match(auth, /barrierDismissible: false/);
assert.match(auth, /SocketService\.instance\.acceptLegal/);
assert.match(socket, /_send\('accept_legal'/);

console.log('Legal protocol source checks passed.');
