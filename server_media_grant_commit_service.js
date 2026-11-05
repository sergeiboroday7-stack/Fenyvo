'use strict';

// Called only after trusted message persistence has succeeded.
// Never grant permissions using an unverified client request.
function createMediaGrantCommitService({ grantStore, mediaForOwner }) {
  if (!grantStore ||
      typeof grantStore.addRecipient !== 'function' ||
      typeof grantStore.allowGroup !== 'function' ||
      typeof mediaForOwner !== 'function') {
    throw new TypeError('Invalid media grant dependencies');
  }

  function validateMedia(message) {
    if (!message || typeof message !== 'object' ||
        typeof message.mediaId !== 'string' ||
        !message.mediaId ||
        typeof message.from !== 'string' ||
        !message.from) {
      throw new TypeError('Invalid committed media message');
    }

    if (!mediaForOwner(message.mediaId, message.from)) {
      throw new Error('MEDIA_OWNER_MISMATCH');
    }
  }

  function commitPrivate(message) {
    validateMedia(message);

    if (typeof message.to !== 'string' || !message.to) {
      throw new TypeError('Missing recipient');
    }

    grantStore.addRecipient(message.mediaId, message.to);
    return { granted: true, mediaId: message.mediaId };
  }

  function commitGroup(message) {
    validateMedia(message);

    if (typeof message.groupId !== 'string' || !message.groupId) {
      throw new TypeError('Missing group identity');
    }

    grantStore.allowGroup(message.mediaId, message.groupId);
    return { granted: true, mediaId: message.mediaId };
  }

  return Object.freeze({ commitPrivate, commitGroup });
}

module.exports = { createMediaGrantCommitService };