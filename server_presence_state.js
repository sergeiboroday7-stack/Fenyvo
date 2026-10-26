'use strict';

// Presence is separate from WebSocket connectivity.
// Background push delivery must not imply public activity.

function createPresenceState({
  getAuthenticatedUser,
  now = Date.now,
  maxAgeMs = 90000,
} = {}) {
  if (typeof getAuthenticatedUser !== 'function') {
    throw new TypeError('Authenticated identity provider required');
  }

  if (typeof now !== 'function') {
    throw new TypeError('Clock required');
  }

  if (!Number.isSafeInteger(maxAgeMs) || maxAgeMs <= 0) {
    throw new TypeError('Invalid activity expiry');
  }

  const sessions = new Map();

  function bind(ws, username) {
    if (!ws || typeof username !== 'string' || !username) {
      return false;
    }

    if (getAuthenticatedUser(ws) !== username) {
      return false;
    }

    sessions.set(username, {
      ws,
      foreground: false,
      updatedAt: now(),
    });

    return true;
  }

  function update(ws, foreground) {
    if (!ws || typeof foreground !== 'boolean') {
      return false;
    }

    const username = getAuthenticatedUser(ws);

    if (!username) {
      return false;
    }

    const session = sessions.get(username);

    if (!session || session.ws !== ws) {
      return false;
    }

    session.foreground = foreground;
    session.updatedAt = now();

    return true;
  }

  function isOnline(username) {
    const session = sessions.get(username);

    if (!session || !session.foreground) {
      return false;
    }

    if (getAuthenticatedUser(session.ws) !== username) {
      return false;
    }

    const age = now() - session.updatedAt;

    return age >= 0 && age < maxAgeMs;
  }

  function disconnect(ws) {
    const username = getAuthenticatedUser(ws);

    if (!username) {
      return false;
    }

    const session = sessions.get(username);

    if (!session || session.ws !== ws) {
      return false;
    }

    sessions.delete(username);

    return true;
  }

  return {
    bind,
    update,
    isOnline,
    disconnect,
  };
}

module.exports = { createPresenceState };