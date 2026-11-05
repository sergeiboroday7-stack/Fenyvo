'use strict';

function createMediaAckRetirementAdapter({
  verifyAck,
  getPending,
  retireMedia,
  purgeLegacy
}) {
  for (const [name, fn] of Object.entries({
    verifyAck, getPending, retireMedia, purgeLegacy
  })) {
    if (typeof fn !== 'function') {
      throw new TypeError('INVALID_ACK_DEPENDENCY: ' + name);
    }
  }

  function acknowledge({
    authenticatedRecipient,
    messageId,
    from,
    to
  }) {
    if (typeof authenticatedRecipient !== 'string' ||
        typeof messageId !== 'string' ||
        typeof from !== 'string' ||
        typeof to !== 'string') {
      return { accepted: false, reason: 'INVALID_ACK' };
    }

    const queue = getPending(to);

    const verification = verifyAck({
      authenticatedUser: authenticatedRecipient,
      messageId,
      from,
      to,
      queue
    });

    if (verification?.allowed !== true) {
      return {
        accepted: false,
        reason: 'ACK_OWNERSHIP_DENIED'
      };
    }

    const matches = Array.isArray(queue)
      ? queue.filter(item =>
          item && !item.__eventType &&
          item.id === messageId
        )
      : [];

    if (matches.length !== 1) {
      return {
        accepted: false,
        reason: 'ACK_PENDING_AMBIGUOUS'
      };
    }

    const stored = matches[0];

    if (stored.from !== from ||
        stored.to !== authenticatedRecipient) {
      return {
        accepted: false,
        reason: 'ACK_IDENTITY_CHANGED'
      };
    }

    if (stored.mediaId != null) {
      // The media identity comes from the persisted queue.
      // It must never be supplied by the ACK payload.
      const result = retireMedia(stored, authenticatedRecipient);

      if (result?.removed !== true ||
          result?.proofRetired !== true) {
        return {
          accepted: false,
          reason: 'RETIREMENT_NOT_COMMITTED'
        };
      }

      // The legacy cleanup can remove statuses and dependent
      // events after the original was durably removed.
      purgeLegacy(authenticatedRecipient, messageId);

      return {
        accepted: true,
        mediaRetired: true
      };
    }

    const removed = purgeLegacy(
      authenticatedRecipient,
      messageId
    );

    if (removed !== true) {
      return {
        accepted: false,
        reason: 'LEGACY_PURGE_NOT_COMMITTED'
      };
    }

    return {
      accepted: true,
      mediaRetired: false
    };
  }

  return Object.freeze({ acknowledge });
}

module.exports = { createMediaAckRetirementAdapter };