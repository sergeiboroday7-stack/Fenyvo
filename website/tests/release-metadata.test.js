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

assert.equal(android.build, 6259);
assert.equal(android.sizeBytes, 77817217);
assert.equal(
  android.sha256,
  '20c3d72c70aaf29624b8b63ff308460691da7811444fcb35fe027c34ba6b3abe',
);
assert.equal(windows.build, 4256);
assert.equal(windows.sizeBytes, 31519845);
assert.equal(
  windows.sha256,
  'eab47d944ad369857837adb163e2477d38aa05040aec3a7bc59cb7b6ea26ee28',
);

for (const source of [index, translations]) {
  assert.match(source, /Android 6259/);
  assert.match(source, /Windows 4256/);
  assert.doesNotMatch(
    source,
    /Android 4251|Windows 4251|Android 4254|Windows 4254|Android 4255|Windows 4255|1\.8\.2\+4251/,
  );
}

assert.match(index, new RegExp(android.sha256, 'i'));
assert.match(index, new RegExp(windows.sha256, 'i'));
assert.match(index, /Fenyvo-1\.8\.2-arm64\.apk/);
assert.match(index, /Fenyvo-1\.8\.2-windows-x64\.zip/);

console.log('Website release metadata matches public Fenyvo Android 6259 and Windows 4256.');
