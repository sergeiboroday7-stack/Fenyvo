'use strict';

// Internal service only. Authentication and the user's explicit
// re-sharing action must be verified by the caller.
// Never expose this service as an unauthenticated endpoint.

function createLegacyMediaRegrantService({
  getMedia,
  getGrant,
  addRecipient,
  isRecipientEligible
}) {
  for (const fn of [getMedia, getGrant, addRecipient, isRecipientEligible]) {
    if (typeof fn !== 'function') {
      throw new TypeError('TRUSTED_DEPENDENCY_REQUIRED');
    }
  }

  function regrant({
    mediaId,
    actor,
    recipient,
    ownerApproved
  }) {
    if (typeof mediaId !== 'string' ||
        !/^[a-zA-Z0-9_-]{1,120}$/.test(mediaId) ||
        typeof actor !== 'string' ||
        !actor.trim() ||
        typeof recipient !== 'string' ||
        !recipient.trim() ||
        recipient !== recipient.trim() ||
        /[\u0000-\u001F\u007F]/.test(recipient) ||
        recipient === actor ||
        ownerApproved !== true) {
      return { ok: false, reason: 'INVALID_OR_UNAPPROVED' };
    }

    // getMedia and getGrant must come from trusted server storage.
    const media = getMedia(mediaId);

    if (!media || typeof media !== 'object' ||
        media.owner !== actor) {
      return { ok: false, reason: 'NOT_OWNER_OR_NOT_FOUND' };
    }

    const existing = getGrant(mediaId);

    if (existing && existing.revoked === true) {
      return { ok: false, reason: 'REVOKED' };
    }

    if (existing && existing.groupId) {
      return { ok: false, reason: 'GROUP_GRANT_NOT_SUPPORTED' };
    }

    // Deny unless the trusted server policy explicitly approves.
    // A missing, malformed or failing resolver must never grant access.
    let recipientEligible = false;
    try {
      recipientEligible =
        isRecipientEligible(actor, recipient, mediaId) === true;
    } catch (_) {
      recipientEligible = false;
    }
    if (!recipientEligible) {
      return { ok: false, reason: 'RECIPIENT_NOT_ELIGIBLE' };
    }
    // Never replace existing recipients; delegate to durable store.
    addRecipient(mediaId, recipient);

    return { ok: true };
  }

  return Object.freeze({ regrant });
}

module.exports = { createLegacyMediaRegrantService };