'use strict';
const crypto = require('node:crypto');

// Small audio rooms. Media stays peer-to-peer; the server only routes signaling.
function createGroupCallSignaling({ send, onlineUsers, getGroup, getMembers,
  isPrivateBusy = () => false, now = Date.now, later = setTimeout,
  cancel = clearTimeout, maxParticipants = 4, notifyStarted = () => {} }) {
  const rooms = new Map(), byUser = new Map();
  const types = new Set(['group_call_get', 'group_call_sync', 'group_call_start',
    'group_call_join', 'group_call_join_request', 'group_call_join_response',
    'group_call_watch', 'group_call_unwatch', 'group_call_stage_invite',
    'group_call_stage_invite_response',
    'group_call_leave', 'group_call_presence', 'group_call_mute',
    'group_call_video', 'group_call_feature', 'group_call_pin', 'group_call_moderate', 'group_call_take_host', 'group_call_signal',
    'group_call_heartbeat']);
  const members = id => getMembers(getGroup(id));
  const emit = (user, type, data) => {
    const ws = onlineUsers.get(user);
    if (ws) send(ws, type, data);
  };
  const snapshot = room => ({ id: room.id, groupId: room.groupId, name: room.name,
    startedBy: room.startedBy, owner: room.owner, featuredUser: room.featuredUser || '',
    awaitingHost: room.awaitingHost === true, pinnedMessage: room.pinnedMessage || null,
    hostGraceUntil: room.hostGraceUntil, limit: maxParticipants,
    participants: [...room.people].map(([user, p]) => ({ user,
      sessionId: p.sessionId, muted: p.muted,
      videoEnabled: p.videoEnabled, away: p.away === true,
      moderator: room.moderators.has(user),
      role: p.viewer ? 'viewer' : user === room.startedBy ? 'host' : room.moderators.has(user) ? 'moderator' : 'guest' })) });
  function broadcast(room) {
    const data = {
      groupId: room.groupId,
      call: rooms.get(room.groupId) === room ? snapshot(room) : null,
    };
    for (const user of members(room.groupId)) emit(user, 'group_call_state', data);
  }
  function clearHostGrace(room) {
    if (room.hostGraceTimer) cancel(room.hostGraceTimer);
    room.hostGraceTimer = null;
    room.hostGraceUntil = null;
  }

  function reconcileHost(room) {
    const onStage = candidate =>
      room.people.get(candidate)?.viewer === false &&
      room.people.get(candidate)?.away !== true;

    // The call creator always reclaims the host role after returning.
    if (onStage(room.owner)) {
      clearHostGrace(room);
      room.startedBy = room.owner;
      room.awaitingHost = false;
      return;
    }
    if (onStage(room.startedBy)) {
      clearHostGrace(room);
      room.awaitingHost = false;
      return;
    }
    // Nobody is promoted automatically. A moderator must explicitly accept
    // responsibility for continuing the call.
    room.startedBy = '';
    room.awaitingHost = true;
    if (!room.hostGraceTimer) {
      room.hostGraceUntil = now() + 5 * 60 * 1000;
      room.hostGraceTimer = later(() => {
        room.hostGraceTimer = null;
        if (rooms.get(room.groupId) === room && room.awaitingHost === true) {
          closeRoom(room, 'Ведущий или модератор не вернулся вовремя');
        }
      }, 5 * 60 * 1000);
      room.hostGraceTimer?.unref?.();
    }
  }

  function closeRoom(room, reason) {
    if (rooms.get(room.groupId) !== room) return;
    rooms.delete(room.groupId);
    cancel(room.timer);
    clearHostGrace(room);
    for (const [member, person] of [...room.people]) {
      room.people.delete(member);
      room.pendingJoins?.delete(member);
      room.approvedJoins?.delete(member);
      room.moderators.delete(member);
      if (byUser.get(member) === room) byUser.delete(member);
      emit(member, 'group_call_left', {
        callId: room.id,
        sessionId: person.sessionId,
        reason,
      });
    }
    broadcast(room);
  }
  function remove(room, user, reason, preserveApproval = false) {
    const person = room.people.get(user);
    if (!person) return;
    room.people.delete(user);
    room.pendingJoins?.delete(user);
    if (!preserveApproval) room.approvedJoins?.delete(user);
    if (byUser.get(user) === room) byUser.delete(user);
    emit(user, 'group_call_left', { callId: room.id, sessionId: person.sessionId, reason });

    reconcileHost(room);
    broadcast(room);
  }
  function prune(room) {
    const allowed = members(room.groupId);
    for (const [user, person] of [...room.people]) {
      if (!allowed.includes(user)) {
        remove(room, user, 'Участник удалён из группы');
      } else if (
        onlineUsers.get(user) !== person.socket ||
        now() - person.seen > 45000
      ) {
        remove(room, user, 'Соединение потеряно');
      }
    }

    for (const [user, request] of [...room.pendingJoins]) {
      if (!request || now() - request.requestedAt >= 45000) {
        room.pendingJoins.delete(user);
      }
    }
  }

  function arm(room) {
    room.timer = later(() => {
      prune(room);
      if (rooms.get(room.groupId) === room) arm(room);
    }, 15000);
    room.timer?.unref?.();
  }
  function handle(ws, user, type, data = {}) {
    if (!types.has(type)) return false;
    if (!data || typeof data !== 'object' || Array.isArray(data)) data = {};
    const requestId = typeof data.requestId === 'string' ? data.requestId.slice(0, 100) : '';
    const error = reason => send(ws, 'group_call_error', { requestId,
      callId: typeof data.callId === 'string' ? data.callId.slice(0, 100) : '', reason });
    if (!user || onlineUsers.get(user) !== ws) { error('Сначала необходимо войти'); return true; }
    if (JSON.stringify(data).length > 200000) { error('Слишком большой пакет'); return true; }
    if (type === 'group_call_sync') {
      const calls = [...rooms.values()].filter(r => members(r.groupId).includes(user)).map(snapshot);
      send(ws, 'group_call_sync', { calls, limit: maxParticipants }); return true;
    }
    const groupId = typeof data.groupId === 'string' ? data.groupId : '';
    if (!groupId || groupId.length > 100 || !members(groupId).includes(user)) {
      error('Звонок доступен только участникам группы'); return true;
    }
    let room = rooms.get(groupId);
    if (room) { prune(room); room = rooms.get(groupId); }
    if (type === 'group_call_get') {
      send(ws, 'group_call_state', { groupId, call: room ? snapshot(room) : null }); return true;
    }
    if (type === 'group_call_watch') {
      if (!requestId) { error('Отсутствует номер запроса'); return true; }
      if (!room || room.id !== data.callId) {
        error('Этот звонок уже завершён'); return true;
      }
      const existing = room.people.get(user);
      if (existing?.requestId === requestId) {
        send(ws, 'group_call_watching', {
          requestId, sessionId: existing.sessionId, call: snapshot(room),
        });
        return true;
      }
      if (byUser.has(user) || isPrivateBusy(user)) {
        error('Сначала завершите текущий звонок'); return true;
      }
      const person = { sessionId: crypto.randomUUID(), requestId, socket: ws,
        muted: true, videoEnabled: false, viewer: true, seen: now(),
        away: false,
        window: now(), signals: 0 };
      room.people.set(user, person); byUser.set(user, room);
      send(ws, 'group_call_watching', {
        requestId, sessionId: person.sessionId, call: snapshot(room),
      });
      broadcast(room);
      return true;
    }
    if (type === 'group_call_join_request') {
      if (!room || room.id !== data.callId) {
        error('Этот звонок уже завершён'); return true;
      }
      if (room.people.has(user) && !room.people.get(user).viewer) {
        send(ws, 'group_call_join_response', {
          groupId, callId: room.id, accepted: true, call: snapshot(room),
        });
        return true;
      }
      // The original host may return immediately. The client still uses the
      // regular request flow, but no temporary host has to approve the owner.
      if (user === room.owner ||
          (room.awaitingHost === true && room.moderators.has(user))) {
        room.approvedJoins.add(user);
        send(ws, 'group_call_join_response', {
          groupId, callId: room.id, accepted: true, call: snapshot(room),
        });
        return true;
      }
      if ((!room.people.get(user)?.viewer && byUser.has(user)) || isPrivateBusy(user)) {
        error('Сначала завершите текущий звонок'); return true;
      }
      const stageCount = [...room.people.values()].filter(p => !p.viewer).length;
      if (stageCount >= maxParticipants) {
        error(`В звонке уже ${maxParticipants} участника`); return true;
      }
      room.pendingJoins.set(user, {
        user,
        videoEnabled: data.videoEnabled !== false,
        requestedAt: now(),
      });
      emit(room.startedBy, 'group_call_join_request', {
        groupId, callId: room.id, user,
        videoEnabled: data.videoEnabled !== false,
      });
      for (const moderator of room.moderators) {
        emit(moderator, 'group_call_join_request', {
          groupId, callId: room.id, user,
          videoEnabled: data.videoEnabled !== false,
        });
      }
      send(ws, 'group_call_join_request_status', {
        groupId, callId: room.id, pending: true,
      });
      return true;
    }
    if (type === 'group_call_join_response') {
      if (!room || room.id !== data.callId || !room.people.has(user)) {
        error('Этот звонок уже завершён'); return true;
      }
      if (room.startedBy !== user && !room.moderators.has(user)) {
        error('Только ведущий или модератор может разрешить вход'); return true;
      }
      const target = typeof data.target === 'string' ? data.target : '';
      const pendingRequest = room.pendingJoins.get(target);
      if (!pendingRequest) return true;
      if (now() - pendingRequest.requestedAt >= 45000) {
        room.pendingJoins.delete(target);
        emit(target, 'group_call_join_response', {
          groupId,
          callId: room.id,
          accepted: false,
          reason: 'Время запроса истекло',
          call: null,
        });
        return true;
      }
      room.pendingJoins.delete(target);
      const stageCount = [...room.people.values()].filter(p => !p.viewer).length;
      const accepted = data.accepted === true && stageCount < maxParticipants;
      if (accepted) room.approvedJoins.add(target);
      emit(target, 'group_call_join_response', {
        groupId, callId: room.id, accepted,
        reason: accepted ? '' : 'Ведущий не разрешил вход',
        call: accepted ? snapshot(room) : null,
      });
      return true;
    }
    if (type === 'group_call_stage_invite') {
      if (!room || room.id !== data.callId || !room.people.has(user)) {
        error('Этот звонок уже завершён'); return true;
      }
      if (room.startedBy !== user && !room.moderators.has(user)) {
        error('Только ведущий или модератор может приглашать на сцену'); return true;
      }
      const target = typeof data.target === 'string' ? data.target : '';
      const targetPerson = room.people.get(target);
      if (!targetPerson?.viewer || target === user) return true;
      const stageCount = [...room.people.values()].filter(p => !p.viewer).length;
      if (stageCount >= maxParticipants) {
        error(`В звонке уже ${maxParticipants} участника`); return true;
      }
      room.approvedJoins.add(target);
      emit(target, 'group_call_stage_invite', {
        groupId, callId: room.id, by: user, call: snapshot(room),
      });
      return true;
    }
    if (type === 'group_call_stage_invite_response') {
      if (!room || room.id !== data.callId || !room.people.get(user)?.viewer) {
        error('Этот звонок уже завершён'); return true;
      }
      if (data.accepted !== true) room.approvedJoins.delete(user);
      return true;
    }
    if (type === 'group_call_start' || type === 'group_call_join') {
      if (!requestId) { error('Отсутствует номер запроса'); return true; }
      if (type === 'group_call_join' && (!room || room.id !== data.callId)) {
        error('Этот звонок уже завершён'); return true;
      }
      const existing = room?.people.get(user);
      if (existing?.requestId === requestId) {
        send(ws, 'group_call_joined', { requestId, sessionId: existing.sessionId, call: snapshot(room) });
        return true;
      }
      const returningAuthority = room && !existing &&
        (user === room.owner ||
         (room.awaitingHost === true && room.moderators.has(user)));
      const viewerInThisRoom =
        existing?.viewer === true && byUser.get(user) === room;
      if (
        room &&
        (!existing || existing.viewer === true) &&
        !room.approvedJoins.has(user) &&
        !returningAuthority
      ) {
        error('Сначала запросите разрешение ведущего'); return true;
      }
      if ((byUser.has(user) && !viewerInThisRoom) || isPrivateBusy(user)) { error('Сначала завершите текущий звонок'); return true; }
      const stageCount = room ? [...room.people.values()].filter(p => !p.viewer).length : 0;
      if (room && stageCount >= maxParticipants) { error(`В звонке уже ${maxParticipants} участника`); return true; }
      const created = !room;
      if (!room) {
        room = { id: crypto.randomUUID(), groupId, name: String(getGroup(groupId)?.name || 'Группа'),
          owner: user, startedBy: user, moderators: new Set(), people: new Map(),
          pendingJoins: new Map(), approvedJoins: new Set(),
          featuredUser: user, awaitingHost: false, pinnedMessage: null,
          hostGraceTimer: null, hostGraceUntil: null };
        rooms.set(groupId, room); arm(room);
        for (const peer of members(groupId)) {
          if (peer !== user) void notifyStarted(peer, snapshot(room));
        }
      }
      const person = { sessionId: crypto.randomUUID(), requestId, socket: ws,
        muted: false, videoEnabled: data.videoEnabled !== false, viewer: false, seen: now(),
        away: false,
        window: now(), signals: 0 };
      room.people.set(user, person); byUser.set(user, room);
      reconcileHost(room);
      room.pendingJoins.delete(user);
      room.approvedJoins.delete(user);
      // The new member learns its lease before anyone can send an SDP offer.
      send(ws, 'group_call_joined', { requestId, sessionId: person.sessionId, call: snapshot(room) });
      broadcast(room);
      return true;
    }
    const person = room?.people.get(user);
    if (!room || room.id !== data.callId || !person || person.sessionId !== data.sessionId) {
      if (type !== 'group_call_leave') error('Вы больше не участвуете в этом звонке');
      return true;
    }
    person.seen = now();
    if (type === 'group_call_unwatch' && person.viewer) {
      remove(room, user, 'Вы вышли из просмотра', data.forStage === true);
      return true;
    }
    if (type === 'group_call_leave') {
      if (user === room.owner && data.endForAll === true) {
        closeRoom(room, 'Автор завершил групповой звонок');
      } else {
        remove(room, user, 'Вы вышли из звонка');
      }
      return true;
    }
    if (type === 'group_call_presence') {
      const away = data.away === true;
      if (person.away !== away) {
        person.away = away;
        reconcileHost(room);
        broadcast(room);
      }
      return true;
    }
    if (type === 'group_call_heartbeat') return true;
    if (type === 'group_call_feature') {
      const canManageBroadcast =
        room.startedBy === user || room.moderators.has(user);
      if (!canManageBroadcast) {
        error('Только ведущий или модератор может управлять эфиром');
        return true;
      }
      const target = typeof data.target === 'string' ? data.target : '';
      if (room.people.get(target)?.viewer !== false) return true;
      room.featuredUser = target;
      broadcast(room);
      return true;
    }
    if (type === 'group_call_pin') {
      const canManageBroadcast =
        room.startedBy === user || room.moderators.has(user);
      if (!canManageBroadcast) {
        error('Только ведущий или модератор может закреплять сообщения');
        return true;
      }
      if (data.message == null) {
        room.pinnedMessage = null;
      } else if (data.message && typeof data.message === 'object' &&
          !Array.isArray(data.message) && JSON.stringify(data.message).length <= 20000) {
        room.pinnedMessage = { ...data.message };
      }
      broadcast(room);
      return true;
    }
    if (type === 'group_call_take_host') {
      if (person.viewer || !room.moderators.has(user) || room.awaitingHost !== true) {
        error('Продолжить эфир вместо автора может только модератор');
        return true;
      }
      clearHostGrace(room);
      room.startedBy = user;
      room.awaitingHost = false;
      broadcast(room);
      return true;
    }
    if (type === 'group_call_mute') {
      if (typeof data.muted === 'boolean' && person.muted !== data.muted) {
        person.muted = data.muted; broadcast(room);
      }
      return true;
    }
    if (type === 'group_call_video') {
      if (typeof data.videoEnabled === 'boolean' && person.videoEnabled !== data.videoEnabled) {
        person.videoEnabled = data.videoEnabled; broadcast(room);
      }
      return true;
    }
    if (type === 'group_call_moderate') {
      const isHost = room.startedBy === user;
      const isModerator = room.moderators.has(user);
      if (!isHost && !isModerator) { error('Только ведущий или модератор может управлять участниками'); return true; }
      const target = typeof data.target === 'string' ? data.target : '';
      const targetPerson = room.people.get(target);
      if (!targetPerson || target === user) return true;
      if (target === room.startedBy || (!isHost && room.moderators.has(target))) return true;
      if (data.action === 'kick') {
        remove(room, target, 'Ведущий удалил вас из звонка');
      } else if (data.action === 'mute') {
        targetPerson.muted = true;
        emit(target, 'group_call_moderation', { callId: room.id, action: 'mute', by: user });
        broadcast(room);
      } else if (data.action === 'video_off') {
        targetPerson.videoEnabled = false;
        emit(target, 'group_call_moderation', { callId: room.id, action: 'video_off', by: user });
        broadcast(room);
      } else if (data.action === 'promote' && user === room.owner) {
        room.moderators.add(target);
        reconcileHost(room);
        broadcast(room);
      } else if (data.action === 'demote' && user === room.owner) {
        room.moderators.delete(target);
        reconcileHost(room);
        broadcast(room);
      }
      return true;
    }
    const peer = room.people.get(data.to);
    if (!peer || data.to === user || peer.sessionId !== data.toSession) {
      // Late ICE from a departed/rejoined participant is harmless and ignored.
      return true;
    }
    if (now() - person.window >= 10000) { person.window = now(); person.signals = 0; }
    if (++person.signals > 1200) return true;
    const signal = data.signal;
    if (!signal || typeof signal !== 'object') return true;
    let safe;
    if (signal.kind === 'offer' || signal.kind === 'answer') {
      if (typeof signal.sdp !== 'string' || !signal.sdp || signal.sdp.length > 150000) return true;
      safe = { kind: signal.kind, sdp: signal.sdp };
    } else if (signal.kind === 'ice') {
      const c = signal.candidate;
      if (!c || typeof c.candidate !== 'string' || c.candidate.length > 8192 ||
          (c.sdpMid != null && (typeof c.sdpMid !== 'string' || c.sdpMid.length > 100)) ||
          (c.sdpMLineIndex != null && (!Number.isInteger(c.sdpMLineIndex) || c.sdpMLineIndex < 0))) return true;
      safe = { kind: 'ice', candidate: { candidate: c.candidate,
        sdpMid: c.sdpMid ?? null, sdpMLineIndex: c.sdpMLineIndex ?? null } };
    } else return true;
    emit(data.to, 'group_call_signal', { callId: room.id, groupId,
      from: user, fromSession: person.sessionId, toSession: peer.sessionId, signal: safe });
    return true;
  }
  return { handle, isBusy: user => byUser.has(user),
    activeUsers(groupId, callId = '') {
      const room = rooms.get(groupId);
      if (!room || (callId && room.id !== callId)) return [];
      return [...room.people.keys()];
    },
    disconnected(user) { const room = byUser.get(user); if (room) remove(room, user, 'Соединение потеряно'); },
    dispose() { for (const room of rooms.values()) { cancel(room.timer); clearHostGrace(room); } rooms.clear(); byUser.clear(); } };
}
module.exports = { createGroupCallSignaling };
