'use strict';

function canonicalizeMessage(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalizeMessage);
  }

  if (value !== null && typeof value === 'object') {
    const sorted = Object.create(null);

    for (const key of Object.keys(value).sort()) {
      sorted[key] = canonicalizeMessage(value[key]);
    }

    return sorted;
  }

  return value;
}

function sameMessageContent(left, right) {
  return JSON.stringify(canonicalizeMessage(left)) ===
    JSON.stringify(canonicalizeMessage(right));
}
function createOfflineMessageQueue({
  getQueues,
  saveQueues,
  commitRecipientQueue,
  logger = console.log,
}) {
  for (const [name, fn] of Object.entries({
    getQueues,
    saveQueues,
    commitRecipientQueue,
    logger,
  })) {
    if (typeof fn !== 'function') {
      throw new TypeError(`Invalid queue dependency: ${name}`);
    }
  }

  function queueOfflineMessage(username, messageData) {
    const offlineMessages = getQueues();

    const existing = Array.isArray(offlineMessages[username])
      ? offlineMessages[username]
      : [];

    const alreadyQueued = existing.some(
      (message) => message?.id === messageData.id
    );

    if (alreadyQueued) {
      const previous = existing.find(
        (message) => message?.id === messageData.id
      );
      if (!sameMessageContent(previous, messageData)) {
        return { conflict: true };
      }
      return { duplicate: true };
    }

    const nextRecipientQueue = [...existing, messageData];

    const nextMessages = {
      ...offlineMessages,
      [username]: nextRecipientQueue,
    };

    // Preserve the original save-before-commit behavior.
    saveQueues(nextMessages);

    commitRecipientQueue(username, nextRecipientQueue);

    logger(
      `💾 Сообщение сохранено в офлайн-очередь для ${username}`
    );
  }

  return { queueOfflineMessage };
}

module.exports = { createOfflineMessageQueue };