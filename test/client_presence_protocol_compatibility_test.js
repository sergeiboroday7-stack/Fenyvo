'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'screens', 'chat_list_screen.dart'),
  'utf8'
);
const languageSource = fs.readFileSync(
  path.join(__dirname, '..', 'lib', 'services', 'app_language_service.dart'),
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
test('command deck shows the real presence count instead of chat totals', () => {
  assert.match(source, /final onlineCount = _onlineUsers\.length;/);
  assert.match(source, /'\$onlineCount'/);
  assert.doesNotMatch(source, /'\$contactCount · \$eventCount'/);
});

test('online count tooltip describes presence instead of server statistics', () => {
  assert.match(source, /_tr\('onlinePeopleDetails', \{\s*'people': onlineCount,\s*\}\)/);
});
test('Russian and Ukrainian navigation distinguish chats from online presence', () => {
  assert.match(languageSource, /'connection': 'ЧАТЫ'/);
  assert.match(languageSource, /'connection': 'ЧАТИ'/);
  assert.equal((languageSource.match(/'connectedShort': 'ОНЛАЙН'/g) || []).length, 2);
});
