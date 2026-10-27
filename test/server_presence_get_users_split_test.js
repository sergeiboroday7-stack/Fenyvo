'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'), 'utf8'
);

const start = source.indexOf(
  'const contactList = presenceProtocol.getContactList(currentUser);'
);
const authoritativeMarker = 'presence_authoritative: true,';
const marker = source.indexOf(authoritativeMarker, start);
const endMarker = '            });';
const end = source.indexOf(endMarker, marker);

assert.ok(start >= 0 && marker > start && end > marker);

const statements = source.slice(start, end + endMarker.length);

function runRoute(online, visible) {
  const events = [];

  const sandbox = {
    currentUser: 'alice',
    ws: {},
    presenceProtocol: {
      getContactList: () => ({
        contacts: ['bob', 'charlie'],
      }),
      getVisibleOnlineList: () => ({
        users: online && visible ? ['bob'] : [],
      }),
    },
    send: (_ws, type, data) => events.push({ type, data }),
  };

  vm.createContext(sandbox);
  vm.runInContext(statements, sandbox);

  return events.map(e => ({
    type: e.type,
    data: JSON.parse(JSON.stringify(e.data)),
  }));
}

test('contacts and online are separate events', () => {
  const events = runRoute(true, true);

  assert.deepEqual(events, [
    {
      type: 'contact_list',
      data: { contacts: ['bob', 'charlie'] },
    },
    {
      type: 'users',
      data: {
        users: ['bob'],
        presence_authoritative: true,
      },
    },
  ]);
});

test('offline contacts remain visible as contacts', () => {
  const events = runRoute(false, true);

  assert.deepEqual(
    events[0].data.contacts,
    ['bob', 'charlie']
  );

  assert.deepEqual(events[1].data.users, []);
});

test('hidden presence never appears as online', () => {
  const events = runRoute(true, false);

  assert.deepEqual(events[1].data.users, []);
});

test('handler uses authenticated presence protocol', () => {
  assert.match(
    statements,
    /presenceProtocol\.getContactList\(currentUser\)/
  );

  assert.match(
    statements,
    /presenceProtocol\.getVisibleOnlineList\(currentUser\)/
  );

  assert.doesNotMatch(
    statements,
    /getAcceptedCommunicationContacts/
  );

  assert.match(
    statements,
    /presence_authoritative:\s*true/
  );
});
