'use strict';

function createGroupMediaCommitService({
  getHistory,
  appendMessage,
  commitMediaGrant,
}) {
  if ([getHistory, appendMessage, commitMediaGrant].some(
    fn => typeof fn !== 'function'
  )) {
    throw new TypeError('Invalid group commit dependencies');
  }

  function stableValue(message) {
    const keys = [
      'id', 'from', 'groupId', 'text', 'messageType',
      'mediaId', 'scope', 'callId', 'replyTo'
    ];
    const result = {};
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(message, key)) {
        result[key] = message[key];
      }
    }
    return JSON.stringify(result);
  }

  function commit(groupId, message) {
    if (!message || typeof message !== 'object' ||
        typeof message.id !== 'string' || !message.id ||
        message.groupId !== groupId) {
      throw new TypeError('Invalid group message');
    }

    const history = getHistory(groupId);
    if (!Array.isArray(history)) {
      throw new TypeError('Invalid group history');
    }

    const previous = history.find(item => item?.id === message.id);

    if (previous) {
      if (stableValue(previous) !== stableValue(message)) {
        return { conflict: true, duplicate: false };
      }

      if (message.mediaId) commitMediaGrant(message);

      return { duplicate: true, conflict: false };
    }

    appendMessage(groupId, message);

    if (message.mediaId) commitMediaGrant(message);

    return { duplicate: false, conflict: false };
  }

  return Object.freeze({ commit });
}

module.exports = { createGroupMediaCommitService };