const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const website = path.resolve(__dirname, '..');
const index = fs.readFileSync(path.join(website, 'index.html'), 'utf8');
const translations = fs.readFileSync(
  path.join(website, 'assets', 'fenyvo-i18n.js'),
  'utf8',
);
const appcast = JSON.parse(
  fs.readFileSync(path.join(website, 'releases', 'appcast.json'), 'utf8'),
);

const android = appcast.platforms.android;
const windows = appcast.platforms.windows;

assert.equal(android.build, 4255);
assert.equal(android.sizeBytes, 77751681);
assert.equal(
  android.sha256,
  '2d95d54b6fe0a9a7d85129deb7c7674ca4621eccb47d80b597fb4c9c5176220a',
);
assert.equal(windows.build, 4255);
assert.equal(windows.sizeBytes, 31505939);
assert.equal(
  windows.sha256,
  '62bd7926be000ab0a96336044477a235d274e92cab7a6f039443ffc56926f60f',
);

for (const source of [index, translations]) {
  assert.match(source, /Android 4255/);
  assert.match(source, /Windows 4255/);
  assert.doesNotMatch(
    source,
    /Android 4251|Windows 4251|Android 4254|Windows 4254|1\.8\.2\+4251/,
  );
}

assert.match(index, new RegExp(android.sha256, 'i'));
assert.match(index, new RegExp(windows.sha256, 'i'));
assert.match(index, /Fenyvo-1\.8\.2-arm64\.apk/);
assert.match(index, /Fenyvo-1\.8\.2-windows-x64\.zip/);

console.log('Website release metadata matches public Fenyvo build 4255.');
