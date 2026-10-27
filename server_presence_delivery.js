'use strict';

function createPresenceDelivery({
  getClients,
  getAuthenticatedUser,
  getVisibleOnlineList,
  getUserStatusData,
  canViewPresence,
  isOpen,
  send,
} = {}) {
  const deps = [
    getClients,
    getAuthenticatedUser,
    getVisibleOnlineList,
    getUserStatusData,
    canViewPresence,
    isOpen,
    send,
  ];

  if (deps.some(fn => typeof fn !== 'function')) {
    throw new TypeError('Presence delivery dependencies required');
  }

  function authenticatedViewer(client) {
    const viewer = getAuthenticatedUser(client);

    return typeof viewer === 'string' && viewer.trim()
      ? viewer
      : null;
  }

  function deliverUserLists() {
    for (const client of getClients()) {
      if (!isOpen(client)) continue;

      const viewer = authenticatedViewer(client);
      if (!viewer) continue;

      const payload = getVisibleOnlineList(viewer);

      if (!payload || !Array.isArray(payload.users)) continue;

      send(client, 'users', {
        ...payload,
        presence_authoritative: true,
      });
    }
  }

  function deliverUserStatus(username) {
    if (typeof username !== 'string' || !username.trim()) {
      return;
    }

    const status = getUserStatusData(username);
    if (!status || typeof status !== 'object') return;

    for (const client of getClients()) {
      if (!isOpen(client)) continue;

      const viewer = authenticatedViewer(client);
      if (!viewer) continue;

      if (canViewPresence(viewer, username) !== true) {
        continue;
      }

      send(client, 'user_status', status);
    }
  }

  function getStatusForViewer(viewer, username) {
    if (
      typeof viewer !== 'string' ||
      !viewer.trim() ||
      typeof username !== 'string' ||
      !username.trim() ||
      canViewPresence(viewer, username) !== true
    ) {
      return null;
    }

    return getUserStatusData(username);
  }

  return {
    deliverUserLists,
    deliverUserStatus,
    getStatusForViewer,
  };
}

module.exports = { createPresenceDelivery };
