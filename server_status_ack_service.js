'use strict';

// Isolated status acknowledgement service.
// Not wired into server.js.
// Existing clients retain their current protocol.

function createStatusAckService({
  getQueues,
  saveQueues,
  commitQueue,
  getAuthenticatedUser,
  isCurrentSocket,
}) {
  for (const fn of [
    getQueues,
    saveQueues,
    commitQueue,
    getAuthenticatedUser,
    isCurrentSocket,
  ]) {
    if (typeof fn !== 'function') {
      throw new TypeError('Status ACK dependency missing');
    }
  }

  function acknowledge({
    ws,
    username,
    messageId,
    type,
  } = {}) {
    if (!ws || typeof username !== 'string' ||
        !username || getAuthenticatedUser(ws) !== username ||
        !isCurrentSocket(username, ws)) {
      return { accepted: false, reason: 'unauthorized' };
    }

    const id = typeof messageId === 'string'
      ? messageId.trim() : '';

    if (!id || !['message_delivered', 'message_read'].includes(type)) {
      return { accepted: false, reason: 'invalid_ack' };
    }

    const queues = getQueues();
    const pending = Object.prototype.hasOwnProperty.call(
      queues, username
    ) ? queues[username] : undefined;

    if (!Array.isArray(pending)) {
      return { accepted: false, reason: 'not_pending' };
    }

    const index = pending.findIndex(item =>
      item?.type === type &&
      item?.data?.messageId?.toString().trim() === id
    );

    if (index < 0) {
      return { accepted: false, reason: 'not_pending' };
    }

    const remaining = pending.filter((_, i) => i !== index);
    const next = { ...queues };

    if (remaining.length) {
      Object.defineProperty(next, username, {
        value: remaining,
        enumerable: true,
        writable: true,
        configurable: true,
      });
    } else {
      delete next[username];
    }

    // Fail closed: persistence must succeed before RAM commit.
    saveQueues(next);
    commitQueue(username, remaining);

    return { accepted: true, reason: 'acknowledged' };
  }

  return { acknowledge };
}

module.exports = { createStatusAckService };