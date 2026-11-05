'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { createLegacyMediaRegrantService } =
  require('../server_legacy_media_regrant_service');

const { createMediaGrantStore } =
  require('../server_media_grant_store');

function setup(t) {
  const dir = fs.mkdtempSync(
    path.join(os.tmpdir(), 'fenyvo-regrant-')
  );

  t.after(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  const filePath = path.join(dir, 'media_grants.json');
  const store = createMediaGrantStore({
    filePath,
    allowedRoot: dir
  });

  const media = {
    media001: { owner: 'alice' },
    media002: { owner: 'alice' }
  };

  const service = createLegacyMediaRegrantService({
    getMedia: id => media[id] || null,
    getGrant: id => store.getGrant(id),
    isRecipientEligible: (owner, recipient) =>
      owner === 'alice' &&
      ['bob', 'charlie'].includes(recipient),    addRecipient: (id, user) => store.addRecipient(id, user)
  });

  return {
    store,
    service,
    reopen: () => createMediaGrantStore({
      filePath, allowedRoot: dir
    })
  };
}

test('owner explicitly approves recipient', t => {
  const s = setup(t);
  const result = s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'bob',
    ownerApproved: true
  });

  assert.equal(result.ok, true);
  assert.deepEqual(
    s.reopen().getGrant('media001').recipients,
    ['bob']
  );
});

test('missing approval grants nothing', t => {
  const s = setup(t);

  assert.equal(s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'bob',
    ownerApproved: false
  }).ok, false);

  assert.equal(s.store.getGrant('media001'), null);
});

test('different actor cannot grant owner media', t => {
  const s = setup(t);

  assert.equal(s.service.regrant({
    mediaId: 'media001',
    actor: 'charlie',
    recipient: 'bob',
    ownerApproved: true
  }).ok, false);

  assert.equal(s.store.getGrant('media001'), null);
});

test('unknown media grants nothing', t => {
  const s = setup(t);

  assert.equal(s.service.regrant({
    mediaId: 'unknown',
    actor: 'alice',
    recipient: 'bob',
    ownerApproved: true
  }).ok, false);
});

test('previous recipients are preserved', t => {
  const s = setup(t);
  s.store.addRecipient('media001', 'bob');

  const result = s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'charlie',
    ownerApproved: true
  });

  assert.equal(result.ok, true);
  assert.deepEqual(
    s.reopen().getGrant('media001').recipients,
    ['bob', 'charlie']
  );
});

test('revoked media cannot be regranted', t => {
  const s = setup(t);
  s.store.revoke('media001');

  assert.equal(s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'bob',
    ownerApproved: true
  }).ok, false);
});

test('existing group grant is not converted to private', t => {
  const s = setup(t);
  s.store.allowGroup('media001', 'group001');

  assert.equal(s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'bob',
    ownerApproved: true
  }).ok, false);
});

test('invalid media ID is rejected', t => {
  const s = setup(t);

  assert.equal(s.service.regrant({
    mediaId: '../media001',
    actor: 'alice',
    recipient: 'bob',
    ownerApproved: true
  }).ok, false);
});
test('recipient with leading whitespace is rejected', t => {
  const s = setup(t);
  const result = s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: ' bob',
    ownerApproved: true
  });
  assert.equal(result.ok, false);
  assert.equal(s.store.getGrant('media001'), null);
});

test('recipient with trailing whitespace is rejected', t => {
  const s = setup(t);
  const result = s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'bob ',
    ownerApproved: true
  });
  assert.equal(result.ok, false);
  assert.equal(s.store.getGrant('media001'), null);
});

test('recipient with control characters is rejected', t => {
  const s = setup(t);
  const result = s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'bob\nadmin',
    ownerApproved: true
  });
  assert.equal(result.ok, false);
  assert.equal(s.store.getGrant('media001'), null);
});
test('non-contact recipient cannot gain a grant', t => {
  const s = setup(t);
  const result = s.service.regrant({
    mediaId: 'media001',
    actor: 'alice',
    recipient: 'unknown_user',
    ownerApproved: true
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'RECIPIENT_NOT_ELIGIBLE');
  assert.equal(s.store.getGrant('media001'), null);
});