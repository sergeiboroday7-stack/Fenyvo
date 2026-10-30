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

assert.equal(android.build, 4254);
assert.equal(android.sizeBytes, 77686145);
assert.equal(
  android.sha256,
  'f0b8965a7f792952253940a1b2dc4335ad8fadf4cd4301c779257b1b6e4f72ab',
);
assert.equal(windows.build, 4254);
assert.equal(windows.sizeBytes, 31490214);
assert.equal(
  windows.sha256,
  '1b7d012c8d8f25db8dc48eacb130b4c3c883d5b3a5273aea5dff772a92d4048f',
);

for (const source of [index, translations]) {
  assert.match(source, /Android 4254/);
  assert.match(source, /Windows 4254/);
  assert.doesNotMatch(source, /Android 4251|Windows 4251|1\.8\.2\+4251/);
}

assert.match(index, new RegExp(android.sha256, 'i'));
assert.match(index, new RegExp(windows.sha256, 'i'));
assert.match(index, /Fenyvo-1\.8\.2-arm64\.apk/);
assert.match(index, /Fenyvo-1\.8\.2-windows-x64\.zip/);

console.log('Website release metadata matches public Fenyvo build 4254.');
