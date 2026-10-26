'use strict';

// Minimal, non-runnable legacy model retained only for the diagnostic tests.
// It records the pre-atomic-write behavior without publishing an old server backup.

function loadOfflineMessages() {
  try {
    if (!fs.existsSync(OFFLINE_MESSAGES_FILE)) {
      fs.writeFileSync(OFFLINE_MESSAGES_FILE, JSON.stringify({}, null, 2), 'utf8');
      return {};
    }

    const data = JSON.parse(fs.readFileSync(OFFLINE_MESSAGES_FILE, 'utf8'));
    if (!data || typeof data !== 'object' || Array.isArray(data)) return {};
    return data;
  } catch (error) {
    console.error('Legacy offline queue load failed:', error);
    return {};
  }
}

function saveOfflineMessages(messages) {
  try {
    fs.writeFileSync(
      OFFLINE_MESSAGES_FILE,
      JSON.stringify(messages, null, 2),
      'utf8',
    );
  } catch (error) {
    console.error('Legacy offline queue save failed:', error);
  }
}

function loadMessageExpirations() {}

function purgeOfflineMessageArtifacts(username, messageId) {
  let removedQueuedOriginal = false;
  let messagesChanged = false;
  const queued = offlineMessages[username];

  if (Array.isArray(queued)) {
    const nextQueue = [];
    for (const item of queued) {
      const eventType = item?.__eventType?.toString().trim() || '';
      const itemMessageId = (eventType ? item?.messageId : item?.id)
        ?.toString()
        .trim() || '';

      if (itemMessageId === messageId && !eventType) {
        removedQueuedOriginal = true;
        messagesChanged = true;
        continue;
      }

      if (
        itemMessageId === messageId &&
        ['message_edited', 'reaction_update', 'pinned_message_updated', 'message_deleted']
          .includes(eventType)
      ) {
        messagesChanged = true;
        continue;
      }

      const replyId = item?.replyTo?.id?.toString().trim() || '';
      if (!eventType && replyId === messageId) {
        const cleanedItem = { ...item };
        delete cleanedItem.replyTo;
        nextQueue.push(cleanedItem);
        messagesChanged = true;
        continue;
      }

      nextQueue.push(item);
    }

    if (messagesChanged) {
      if (nextQueue.length === 0) delete offlineMessages[username];
      else offlineMessages[username] = nextQueue;
      saveOfflineMessages(offlineMessages);
    }
  }

  const queuedStatuses = offlineMessageStatus[username];
  if (Array.isArray(queuedStatuses)) {
    const nextStatuses = queuedStatuses.filter(
      item => item?.data?.messageId?.toString().trim() !== messageId,
    );
    if (nextStatuses.length !== queuedStatuses.length) {
      if (nextStatuses.length === 0) delete offlineMessageStatus[username];
      else offlineMessageStatus[username] = nextStatuses;
      saveOfflineMessageStatus(offlineMessageStatus);
    }
  }

  return removedQueuedOriginal;
}

function deletePrivateMessageForEveryone() {}
