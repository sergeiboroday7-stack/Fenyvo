'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { createLegacyMediaRegrantHandler } =
  require('../server_legacy_media_regrant_handler');
const { createMediaGrantStore } =
  require('../server_media_grant_store');

function setup(t) {
  const dir = fs.mkdtempSync(
    path.join(os.tmpdir(), 'fenyvo-auth-regrant-')
  );

  t.after(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  const store = createMediaGrantStore({
    filePath: path.join(dir, 'media_grants.json'),
    allowedRoot: dir
  });

  // Test stand-in for an authenticated server session.
  const sessions = new WeakMap();
  const aliceSession = {};
  const attackerSession = {};
  sessions.set(aliceSession, 'alice');
  sessions.set(attackerSession, 'charlie');

  const handler = createLegacyMediaRegrantHandler({
    getAuthenticatedUsername: session =>
      sessions.get(session) || null,
    getMedia: id =>
      id === 'media001' ? { owner: 'alice' } : null,
    getGrant: id => store.getGrant(id),
    isRecipientEligible: (owner, recipient) =>
      owner === 'alice' &&
      ['bob', 'charlie'].includes(recipient),    addRecipient: (id, user) =>
      store.addRecipient(id, user)
  });

  return { handler, store, aliceSession, attackerSession };
}

test('authenticated owner can explicitly regrant', t => {
  const s = setup(t);

  assert.equal(s.handler.handle(s.aliceSession, {
    mediaId: 'media001',
    recipient: 'bob',
    confirm: true
  }).ok, true);

  assert.deepEqual(
    s.store.getGrant('media001').recipients,
    ['bob']
  );
});

test('unauthenticated session cannot regrant', t => {
  const s = setup(t);

  assert.equal(s.handler.handle({}, {
    mediaId: 'media001',
    recipient: 'bob',
    confirm: true
  }).ok, false);

  assert.equal(s.store.getGrant('media001'), null);
});

test('spoofed actor and owner fields are ignored', t => {
  const s = setup(t);

  assert.equal(s.handler.handle(s.attackerSession, {
    actor: 'alice',
    owner: 'alice',
    mediaId: 'media001',
    recipient: 'bob',
    confirm: true
  }).ok, false);

  assert.equal(s.store.getGrant('media001'), null);
});

test('explicit confirmation is required', t => {
  const s = setup(t);

  assert.equal(s.handler.handle(s.aliceSession, {
    mediaId: 'media001',
    recipient: 'bob'
  }).ok, false);

  assert.equal(s.store.getGrant('media001'), null);
});

test('unknown media is refused', t => {
  const s = setup(t);

  assert.equal(s.handler.handle(s.aliceSession, {
    mediaId: 'missing',
    recipient: 'bob',
    confirm: true
  }).ok, false);

  assert.equal(s.store.getGrant('missing'), null);
});

test('revoked media remains denied', t => {
  const s = setup(t);
  s.store.revoke('media001');

  assert.equal(s.handler.handle(s.aliceSession, {
    mediaId: 'media001',
    recipient: 'bob',
    confirm: true
  }).ok, false);
});
test('authenticated owner cannot regrant to an unaccepted contact', t => {
  const s = setup(t);
  const result = s.handler.handle(s.aliceSession, {
    mediaId: 'media001',
    recipient: 'unknown_user',
    confirm: true
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'RECIPIENT_NOT_ELIGIBLE');
  assert.equal(s.store.getGrant('media001'), null);
});