'use strict';

function normalizeUsernames(value) {
  if (!Array.isArray(value)) return [];

  const result = [];
  const seen = new Set();

  for (const item of value) {
    if (typeof item !== 'string') continue;

    const username = item.trim();
    if (!username) continue;

    const key = username.toLowerCase();
    if (seen.has(key)) continue;

    seen.add(key);
    result.push(username);
  }

  return result;
}

function createPresenceProtocol({
  getAcceptedContacts,
  isOnline,
  canViewPresence,
} = {}) {
  if (
    typeof getAcceptedContacts !== 'function' ||
    typeof isOnline !== 'function' ||
    typeof canViewPresence !== 'function'
  ) {
    throw new TypeError('Presence protocol dependencies required');
  }

  function getContactList(viewer) {
    if (typeof viewer !== 'string' || !viewer.trim()) {
      return { contacts: [] };
    }

    return {
      contacts: normalizeUsernames(getAcceptedContacts(viewer)),
    };
  }

  function getVisibleOnlineList(viewer) {
    if (typeof viewer !== 'string' || !viewer.trim()) {
      return { users: [] };
    }

    const contacts = getContactList(viewer).contacts;

    return {
      users: contacts.filter(username =>
        canViewPresence(viewer, username) === true &&
        isOnline(username) === true
      ),
    };
  }

  return {
    getContactList,
    getVisibleOnlineList,
  };
}

module.exports = {
  createPresenceProtocol,
  normalizeUsernames,
};