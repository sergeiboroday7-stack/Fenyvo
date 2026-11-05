'use strict';

// Preliminary authorization policy.
// This module does not modify persistent media metadata.
// All grants must originate from trusted server-side events.

function createMediaAccessService({
  getMedia,
  getGroup,
  isGroupMember,
  getGrant,
}) {
  for (const fn of [getMedia, getGroup, isGroupMember, getGrant]) {
    if (typeof fn !== 'function') {
      throw new TypeError('Missing trusted dependency');
    }
  }

  function canDownload(mediaId, username) {
    if (typeof mediaId !== 'string' ||
        typeof username !== 'string' ||
        !mediaId.trim() ||
        !username.trim()) {
      return false;
    }

    const media = getMedia(mediaId);
    if (!media || typeof media !== 'object') {
      return false;
    }

    if (media.owner === username) {
      return true;
    }

    // No implicit access based on mediaId alone.
    const grant = getGrant(mediaId);

    if (!grant || typeof grant !== 'object') {
      return false;
    }

    if (grant.revoked === true ||
        (Number.isFinite(grant.expiresAt) &&
         Date.now() >= grant.expiresAt)) {
      return false;
    }

    if (Array.isArray(grant.recipients) &&
        grant.recipients.includes(username)) {
      return true;
    }

    if (typeof grant.groupId === 'string' &&
        grant.groupId.length > 0) {
      const group = getGroup(grant.groupId);

      if (!group) return false;

      return isGroupMember(group, username) === true;
    }

    return false;
  }

  return Object.freeze({ canDownload });
}

module.exports = { createMediaAccessService };