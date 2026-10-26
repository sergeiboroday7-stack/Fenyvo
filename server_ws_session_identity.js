'use strict';

function createServerSessionIdentity() {
  const identities = new WeakMap();

  function assertSocket(socket) {
    if (!socket || typeof socket !== 'object') {
      throw new TypeError('Invalid WebSocket session');
    }
  }

  function bindAuthenticated(socket, userId) {
    assertSocket(socket);

    if (typeof userId !== 'string' ||
        !userId.trim() ||
        userId !== userId.trim() ||
        userId.length > 128) {
      throw new TypeError('Invalid authenticated user');
    }

    if (identities.has(socket)) {
      throw new Error('WebSocket identity already bound');
    }

    identities.set(socket, userId);
  }

  function getAuthenticatedUser(socket) {
    if (!socket || typeof socket !== 'object') {
      return null;
    }

    return identities.get(socket) || null;
  }

  function revoke(socket) {
    assertSocket(socket);
    return identities.delete(socket);
  }

  return Object.freeze({
    bindAuthenticated,
    getAuthenticatedUser,
    revoke,
  });
}

module.exports = { createServerSessionIdentity };