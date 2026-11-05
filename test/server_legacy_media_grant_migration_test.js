'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { planLegacyMediaGrants } =
  require('../server_legacy_media_grant_migration');

function fixture() {
  const media = Object.create(null);

  for (let i = 1; i <= 94; i++) {
    media['media_' + i] = { owner: 'alice' };
  }

  const groups = {
    group_1: { members: ['alice', 'bob'] }
  };

  const histories = { group_1: [] };

  for (let i = 1; i <= 8; i++) {
    histories.group_1.push({
      mediaId: 'media_' + i,
      from: 'alice',
      groupId: 'group_1'
    });
  }

  return { media, groups, histories };
}

test('94 files: 8 candidates and 86 unconfirmed', () => {
  const result = planLegacyMediaGrants(fixture());

  assert.equal(result.summary.indexedMedia, 94);
  assert.equal(result.summary.groupCandidates, 8);
  assert.equal(result.summary.unconfirmedMedia, 86);
  assert.equal(result.summary.approvedForProductionWrite, false);
});

test('proposal matches version 1 grant entry shape', () => {
  const result = planLegacyMediaGrants(fixture());
  const entry = result.proposal[0];

  assert.deepEqual(entry.grant, {
    recipients: [],
    groupId: 'group_1',
    expiresAt: null,
    revoked: false
  });
});

test('wrong media owner is rejected', () => {
  const data = fixture();
  data.media.media_1.owner = 'charlie';

  const result = planLegacyMediaGrants(data);

  assert.equal(result.summary.groupCandidates, 7);
  assert.equal(result.summary.invalidReferences, 1);
});

test('sender absent from group is rejected', () => {
  const data = fixture();
  data.groups.group_1.members = ['bob'];

  const result = planLegacyMediaGrants(data);

  assert.equal(result.summary.groupCandidates, 0);
});

test('conflicting group claim is rejected', () => {
  const data = fixture();

  data.groups.group_2 = { members: ['alice'] };
  data.histories.group_2 = [{
    mediaId: 'media_1',
    from: 'alice',
    groupId: 'group_2'
  }];

  const result = planLegacyMediaGrants(data);

  assert.equal(result.summary.conflicts, 1);
  assert.equal(result.summary.groupCandidates, 7);
});

test('invalid group ID is rejected', () => {
  const data = fixture();

  data.groups['../bad'] = { members: ['alice'] };
  data.histories['../bad'] = [{
    mediaId: 'media_1',
    from: 'alice',
    groupId: '../bad'
  }];

  const result = planLegacyMediaGrants(data);

  assert.equal(result.summary.invalidReferences, 1);
  assert.equal(result.summary.groupCandidates, 7);
});

test('missing or invalid storage inputs fail closed', () => {
  assert.throws(
    () => planLegacyMediaGrants({
      media: null,
      groups: {},
      histories: {}
    }),
    /INVALID_MIGRATION_INPUT/
  );
});

test('proposal does not mutate original data', () => {
  const data = fixture();
  const before = JSON.stringify(data);

  planLegacyMediaGrants(data);

  assert.equal(JSON.stringify(data), before);
});