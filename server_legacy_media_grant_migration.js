'use strict';

// Pure migration planning only.
// Does not read files or write permissions.

function isObject(value) {
  return value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value);
}

function validId(value) {
  return typeof value === 'string' &&
    /^[a-zA-Z0-9_-]{1,120}$/.test(value);
}

function planLegacyMediaGrants({ media, groups, histories }) {
  if (!isObject(media) || !isObject(groups) ||
      !isObject(histories)) {
    throw new TypeError('INVALID_MIGRATION_INPUT');
  }

  const candidates = new Map();
  const rejected = new Set();
  let references = 0;
  let invalid = 0;
  let conflicting = 0;

  for (const [groupId, messages] of Object.entries(histories)) {
    if (!Array.isArray(messages)) {
      throw new TypeError('INVALID_GROUP_HISTORY');
    }

    for (const message of messages) {
      if (!isObject(message) ||
          typeof message.mediaId !== 'string' ||
          message.mediaId.length === 0) {
        continue;
      }

      references++;

      const id = message.mediaId;
      const record = Object.hasOwn(media, id) ? media[id] : null;
      const group = Object.hasOwn(groups, groupId) ? groups[groupId] : null;

      const valid =
        validId(id) &&
        validId(groupId) &&
        isObject(record) &&
        isObject(group) &&
        typeof record.owner === 'string' &&
        record.owner.length > 0 &&
        record.owner !== 'legacy' &&
        record.owner === message.from &&
        message.groupId === groupId &&
        Array.isArray(group.members) &&
        group.members.length > 0 &&
        group.members.every(member =>
          typeof member === 'string' && member.length > 0) &&
        group.members.includes(message.from);

      if (!valid) {
        invalid++;
        rejected.add(id);
        continue;
      }

      const previous = candidates.get(id);

      if (previous &&
          (previous.groupId !== groupId ||
           previous.owner !== message.from)) {
        conflicting++;
        rejected.add(id);
        continue;
      }

      candidates.set(id, {
        groupId,
        owner: message.from
      });
    }
  }

  for (const id of rejected) {
    candidates.delete(id);
  }

  const proposal = [...candidates.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([mediaId, claim]) => ({
      mediaId,
      grant: {
        recipients: [],
        groupId: claim.groupId,
        expiresAt: null,
        revoked: false
      }
    }));

  const indexed = Object.keys(media).length;

  return Object.freeze({
    summary: Object.freeze({
      indexedMedia: indexed,
      groupReferences: references,
      groupCandidates: proposal.length,
      invalidReferences: invalid,
      conflicts: conflicting,
      unconfirmedMedia: indexed - proposal.length,
      historicalMembershipVerified: false,
      privateRecipientsVerified: false,
      approvedForProductionWrite: false
    }),
    proposal
  });
}

module.exports = { planLegacyMediaGrants };