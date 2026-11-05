'use strict';

const VALID_ID = /^[a-zA-Z0-9_-]{1,120}$/;

function createMediaRecoveryProofIssuer({
  getAuthenticatedSender,
  getPending,
  getMedia,
  getGrant,
  journal
}) {
  for (const [name, fn] of Object.entries({
    getAuthenticatedSender, getPending, getMedia, getGrant
  })) {
    if (typeof fn !== 'function') {
      throw new TypeError('INVALID_DEPENDENCY: ' + name);
    }
  }

  if (!journal || typeof journal.record !== 'function') {
    throw new TypeError('TRUSTED_JOURNAL_REQUIRED');
  }

  const valid = value =>
    typeof value === 'string' && VALID_ID.test(value);

  function issue(socket, message) {
    const sender = getAuthenticatedSender(socket);

    if (!valid(sender)) {
      return { issued: false, reason: 'UNAUTHENTICATED' };
    }

    if (!message || typeof message !== 'object' ||
        Array.isArray(message) ||
        !['id','mediaId','from','to'].every(
          field => valid(message[field])
        ) ||
        message.from !== sender) {
      return { issued: false, reason: 'INVALID_IDENTITY' };
    }

    const media = getMedia(message.mediaId);
    if (!media || media.owner !== sender) {
      return { issued: false, reason: 'OWNER_MISMATCH' };
    }

    // Require exactly one server-persisted matching queue item.
    const pending = getPending(message.to);
    if (!Array.isArray(pending)) {
      return { issued: false, reason: 'NOT_PENDING' };
    }

    const matches = pending.filter(item =>
      item && !item.__eventType && item.id === message.id
    );

    if (matches.length !== 1) {
      return {
        issued: false,
        reason: matches.length > 1
          ? 'AMBIGUOUS_MESSAGE'
          : 'NOT_PENDING'
      };
    }

    const stored = matches[0];

    if (stored.mediaId !== message.mediaId ||
        stored.from !== sender ||
        stored.to !== message.to) {
      return { issued: false, reason: 'QUEUE_MISMATCH' };
    }

    const grant = getGrant(message.mediaId);

    if (grant?.revoked === true) {
      return { issued: false, reason: 'REVOKED' };
    }

    if (grant?.groupId) {
      return { issued: false, reason: 'GROUP_GRANT' };
    }

    if (grant?.expiresAt != null &&
        (!Number.isSafeInteger(grant.expiresAt) ||
         Date.now() >= grant.expiresAt)) {
      return { issued: false, reason: 'EXPIRED' };
    }

    const proof = {
      id: stored.id,
      mediaId: stored.mediaId,
      from: stored.from,
      to: stored.to
    };

    // Journal is signed. Any write error propagates, so the caller
    // must not acknowledge or deliver after a failed proof commit.
    const recorded = journal.record(proof);

    return {
      issued: true,
      duplicate: recorded === false
    };
  }

  return Object.freeze({ issue });
}

module.exports = { createMediaRecoveryProofIssuer };