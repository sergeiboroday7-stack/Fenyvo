'use strict';
const crypto = require('node:crypto');

// Small audio rooms. Media stays peer-to-peer; the server only routes signaling.
function createGroupCallSignaling({ send, onlineUsers, getGroup, getMembers,
  isPrivateBusy = () => false, now = Date.now, later = setTimeout,
  cancel = clearTimeout, maxParticipants = 4 }) {
  const rooms = new Map(), byUser = new Map();
  const types = new Set(['group_call_get', 'group_call_sync', 'group_call_start',
    'group_call_join', 'group_call_leave', 'group_call_mute',
    'group_call_signal', 'group_call_heartbeat']);
  const members = id => getMembers(getGroup(id));
  const emit = (user, type, data) => {
    const ws = onlineUsers.get(user);
    if (ws) send(ws, type, data);
  };
  const snapshot = room => ({ id: room.id, groupId: room.groupId, name: room.name,
    startedBy: room.startedBy, limit: maxParticipants,
    participants: [...room.people].map(([user, p]) => ({ user,
      sessionId: p.sessionId, muted: p.muted })) });
  function broadcast(room) {
    const data = { groupId: room.groupId, call: room.people.size ? snapshot(room) : null };
    for (const user of members(room.groupId)) emit(user, 'group_call_state', data);
  }
  function remove(room, user, reason) {
    const person = room.people.get(user);
    if (!person) return;
    room.people.delete(user);
    if (byUser.get(user) === room) byUser.delete(user);
    emit(user, 'group_call_left', { callId: room.id, sessionId: person.sessionId, reason });
    if (!room.people.size) { rooms.delete(room.groupId); cancel(room.timer); }
    broadcast(room);
  }
  function prune(room) {
    const allowed = members(room.groupId);
    for (const [user, person] of [...room.people]) {
      if (!allowed.includes(user)) remove(room, user, 'Участник удалён из группы');
      else if (onlineUsers.get(user) !== person.socket || now() - person.seen > 45000) remove(room, user, 'Соединение потеряно');
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
      if (byUser.has(user) || isPrivateBusy(user)) { error('Сначала завершите текущий звонок'); return true; }
      if (room && room.people.size >= maxParticipants) { error(`В звонке уже ${maxParticipants} участника`); return true; }
      const created = !room;
      if (!room) {
        room = { id: crypto.randomUUID(), groupId, name: String(getGroup(groupId)?.name || 'Группа'),
          startedBy: user, people: new Map() };
        rooms.set(groupId, room); arm(room);
      }
      const person = { sessionId: crypto.randomUUID(), requestId, socket: ws, muted: false, seen: now(),
        window: now(), signals: 0 };
      room.people.set(user, person); byUser.set(user, room);
      // The new member learns its lease before anyone can send an SDP offer.
      send(ws, 'group_call_joined', { requestId, sessionId: person.sessionId, call: snapshot(room) });
      broadcast(room);
      if (created) for (const peer of members(groupId)) {
        if (peer !== user && !byUser.has(peer) && !isPrivateBusy(peer)) {
          emit(peer, 'group_call_invite', { call: snapshot(room) });
        }
      }
      return true;
    }
    const person = room?.people.get(user);
    if (!room || room.id !== data.callId || !person || person.sessionId !== data.sessionId) {
      if (type !== 'group_call_leave') error('Вы больше не участвуете в этом звонке');
      return true;
    }
    person.seen = now();
    if (type === 'group_call_leave') { remove(room, user, 'Вы вышли из звонка'); return true; }
    if (type === 'group_call_heartbeat') return true;
    if (type === 'group_call_mute') {
      if (typeof data.muted === 'boolean' && person.muted !== data.muted) {
        person.muted = data.muted; broadcast(room);
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
    disconnected(user) { const room = byUser.get(user); if (room) remove(room, user, 'Соединение потеряно'); },
    dispose() { for (const room of rooms.values()) cancel(room.timer); rooms.clear(); byUser.clear(); } };
}
module.exports = { createGroupCallSignaling };
