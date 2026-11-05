'use strict';

// Transport-level adapter for authenticated legacy media re-sharing.
// Persistent storage and authorization policy remain in separate modules.

function createLegacyMediaRegrantProtocol({
  getAuthenticatedUser,
  getActiveSocket,
  regrantHandler,
  send
}) {
  for (const fn of [
    getAuthenticatedUser,
    getActiveSocket,
    send
  ]) {
    if (typeof fn !== 'function') {
      throw new TypeError('TRUSTED_DEPENDENCY_REQUIRED');
    }
  }

  function handle(ws, currentUser, data) {
    // Optional correlation token. Old clients need no changes.
    const requestId =
      typeof data?.requestId === 'string' &&
      /^[A-Za-z0-9_-]{1,64}$/.test(data.requestId)
        ? data.requestId
        : null;

    const reply = (result) => {
      const payload = requestId === null
        ? result
        : { ...result, requestId };

      send(ws, 'legacy_media_regrant_result', payload);
    };
    const authenticated = getAuthenticatedUser(ws);

    if (
      !authenticated ||
      authenticated !== currentUser ||
      getActiveSocket(authenticated) !== ws ||
      !regrantHandler ||
      typeof regrantHandler.handle !== 'function'
    ) {
      reply({
        ok: false,
        reason: 'UNAUTHENTICATED'
      });
      return;
    }

    try {
      const request = {
        mediaId: data?.mediaId,
        recipient: data?.recipient,
        confirm: data?.confirm
      };

      const result = regrantHandler.handle(ws, request);

      reply(result);
    } catch (_) {
      reply({
        ok: false,
        reason: 'REGRANT_FAILED'
      });
    }
  }

  return Object.freeze({ handle });
}

module.exports = { createLegacyMediaRegrantProtocol };