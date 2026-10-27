const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

test('current product metadata uses the Fenyvo brand', () => {
  const pubspec = read('pubspec.yaml');
  assert.match(pubspec, /^name: fenyvo$/m);
  assert.match(pubspec, /^description: Fenyvo messenger for Android and Windows$/m);
  assert.match(pubspec, /^version: 1\.8\.2\+4252$/m);
});

test('current user-facing source contains no retired product name', () => {
  const currentSources = [
    read('server.js'),
    read('lib/services/socket_service.dart'),
  ].join('\n');

  assert.doesNotMatch(currentSources, /Spartan Chat|SPARTAN CHAT|SPARTAN AI/);
});

test('Fenyvo server URL is primary and the legacy key remains a fallback', () => {
  const config = read('lib/config/server_config.dart');
  assert.match(config, /'FENYVO_SERVER_URL'/);
  assert.match(config, /'SPARTAN_SERVER_URL'/);
});
