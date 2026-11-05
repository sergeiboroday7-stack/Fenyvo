'use strict';

const { createLegacyMediaRegrantService } =
  require('./server_legacy_media_regrant_service');

function createLegacyMediaRegrantHandler({
  getAuthenticatedUsername,
  getMedia,
  getGrant,
  addRecipient,
  isRecipientEligible
}) {
  if (typeof getAuthenticatedUsername !== 'function') {
    throw new TypeError('TRUSTED_AUTH_RESOLVER_REQUIRED');
  }

  const service = createLegacyMediaRegrantService({
    getMedia, getGrant, addRecipient, isRecipientEligible
  });

  function handle(session, request) {
    const actor = getAuthenticatedUsername(session);

    if (typeof actor !== 'string' || !actor.trim()) {
      return { ok: false, reason: 'UNAUTHENTICATED' };
    }

    if (!request || typeof request !== 'object' ||
        Array.isArray(request) ||
        request.confirm !== true) {
      return { ok: false, reason: 'CONFIRMATION_REQUIRED' };
    }

    // Never trust request.actor or request.owner.
    // Actor is derived only from the authenticated session.
    return service.regrant({
      mediaId: request.mediaId,
      actor,
      recipient: request.recipient,
      ownerApproved: true
    });
  }

  return Object.freeze({ handle });
}

module.exports = { createLegacyMediaRegrantHandler };