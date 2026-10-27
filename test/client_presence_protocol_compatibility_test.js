'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'screens', 'chat_list_screen.dart'),
  'utf8'
);

const usersStart = source.indexOf("if (type == 'users')");
const statusStart = source.indexOf("if (type == 'user_status')", usersStart);

assert.ok(usersStart >= 0 && statusStart > usersStart);

const usersHandler = source.slice(usersStart, statusStart);
const statusHandler = source.slice(statusStart, statusStart + 500);

test('legacy users snapshots cannot mark every contact online', () => {
  assert.match(
    usersHandler,
    /if \(data\['presence_authoritative'\] == true\) \{\s*_presence\.replaceOnline\(users\);\s*\}/
  );
});

test('point presence updates remain active for old and new servers', () => {
  assert.match(
    statusHandler,
    /_presence\.updateUser\(username, online: data\['online'\] == true\)/
  );
});
