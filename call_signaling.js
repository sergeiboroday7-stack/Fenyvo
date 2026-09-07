'use strict';
const crypto = require('node:crypto');

// Ephemeral signaling only. SDP and credentials are never sent through FCM.
function createCallSignaling({ send, onlineUsers, registeredUsers, push,
  now = Date.now, later = setTimeout, cancel = clearTimeout,
  isExternallyBusy = () => false }) {
  const calls = new Map();
  const byUser = new Map();
  const types = new Set(['call_offer', 'call_answer', 'call_ice_candidate',
    'call_reject', 'call_end', 'call_connected', 'get_pending_call']);
  const emit = (user, type, data) => {
    const socket = onlineUsers.get(user);
    if (socket) send(socket, type, data);
  };
  const arm = (call, ms) => {
    cancel(call.timer);
    call.timer = later(() => finish(call, 'timeout'), ms);
    call.timer?.unref?.();
  };
  function finish(call, reason = 'ended') {
    if (calls.get(call.id) !== call) return;
    calls.delete(call.id);
    for (const user of [call.from, call.to]) {
      if (byUser.get(user) === call.id) byUser.delete(user);
    }
    cancel(call.timer);
    cancel(call.disconnectTimer);
    emit(call.from, 'call_end', { callId: call.id, from: call.to, reason });
    emit(call.to, 'call_end', { callId: call.id, from: call.from, reason });
    void push(call.to, { type: 'call_cancel', callId: call.id, to: call.to,
      expiresAt: String(now() + 75000) }).catch(() => {});
  }
  function handle(ws, user, type, data = {}) {
    if (!types.has(type)) return false;
    const id = String(data.callId || '').trim();
    const error = reason => send(ws, 'call_error', { callId: id, reason });
    if (!user || onlineUsers.get(user) !== ws) { error('Сначала необходимо войти'); return true; }
    if (type === 'get_pending_call') {
      const call = calls.get(byUser.get(user));
      if (call && call.to === user && call.state === 'ringing' && now() < call.expiresAt) {
        emit(user, 'call_offer', call.offer);
        for (const candidate of call.candidates) emit(user, 'call_ice_candidate', candidate);
      } else send(ws, 'pending_call_empty', { callId: id });
      return true;
    }
    const to = String(data.to || '').trim();
    if (!id || id.length > 100 || !to || to === user ||
        !Object.prototype.hasOwnProperty.call(registeredUsers, to)) {
      error('Некорректные данные звонка'); return true;
    }
    if (JSON.stringify(data).length > 200000) { error('Слишком большой пакет звонка'); return true; }
    if (type === 'call_offer') {
      if (data.sdp?.type !== 'offer' || typeof data.sdp.sdp !== 'string' || !data.sdp.sdp) {
        error('Некорректное предложение звонка'); return true;
      }
      const existing = calls.get(id);
      if (existing?.from === user && existing.to === to) return true;
      if (existing || byUser.has(user) || byUser.has(to) || isExternallyBusy(user) || isExternallyBusy(to)) {
        send(ws, 'call_reject', { callId: id, from: to, reason: 'busy' }); return true;
      }
      const call = { id, from: user, to, state: 'ringing', expiresAt: now() + 75000,
        token: crypto.randomBytes(32).toString('hex'), candidates: [] };
      call.offer = { callId: id, from: user, to, video: data.video === true,
        sdp: data.sdp, expiresAt: call.expiresAt, callToken: call.token };
      calls.set(id, call); byUser.set(user, id); byUser.set(to, id); arm(call, 75000);
      emit(to, 'call_offer', call.offer);
      // Online does not mean foreground: a phone may have a suspended socket.
      void push(to, { type: 'call_invite', callId: id, sender: user, to,
        video: String(data.video === true), expiresAt: String(call.expiresAt),
        callToken: call.token }).then(ok => {
        if (!ok && !onlineUsers.has(to) && calls.get(id) === call && call.state === 'ringing') {
          emit(user, 'call_unavailable', { callId: id, from: to });
          finish(call, 'unavailable');
        }
      }).catch(() => { if (!onlineUsers.has(to)) finish(call, 'unavailable'); });
      return true;
    }
    const call = calls.get(id);
    if (!call || !((call.from === user && call.to === to) || (call.to === user && call.from === to))) {
      error('Звонок уже завершён'); return true;
    }
    if (type === 'call_answer') {
      if (user !== call.to || call.state !== 'ringing' || data.sdp?.type !== 'answer' ||
          typeof data.sdp.sdp !== 'string' || !data.sdp.sdp) {
        error('Некорректный ответ на звонок'); return true;
      }
      // Older foreground clients do not emit call_connected. Their own 45s
      // connection timeout sends call_end, so keep the wire protocol compatible.
      call.state = 'active'; call.candidates = []; cancel(call.timer);
      emit(to, type, { callId: id, from: user, to, sdp: data.sdp });
    } else if (type === 'call_ice_candidate') {
      if (typeof data.candidate?.candidate !== 'string' || data.candidate.candidate.length > 8192) return true;
      const packet = { callId: id, from: user, to, candidate: data.candidate };
      if (user === call.from && call.state === 'ringing' && call.candidates.length < 256) call.candidates.push(packet);
      emit(to, type, packet);
    } else if (type === 'call_connected') {
      if (call.state !== 'ringing') { call.state = 'active'; cancel(call.timer); }
    } else {
      if (type === 'call_reject') emit(to, type, { callId: id, from: user, reason: data.reason === 'busy' ? 'busy' : 'declined' });
      finish(call, type === 'call_reject' ? 'declined' : 'ended');
    }
    return true;
  }
  function authorize(id, token) {
    const call = calls.get(id);
    if (!call || call.state !== 'ringing' || now() >= call.expiresAt ||
        typeof token !== 'string' || !/^[0-9a-f]{64}$/.test(token)) return null;
    return crypto.timingSafeEqual(Buffer.from(token), Buffer.from(call.token)) ? call : null;
  }
  return { handle, authorize, isBusy: user => byUser.has(user),
    decline(id, token) {
      const call = authorize(id, token);
      if (!call) return false;
      emit(call.from, 'call_reject', { callId: id, from: call.to, reason: 'declined' });
      finish(call, 'declined'); return true;
    },
    disconnected(user) {
      const call = calls.get(byUser.get(user));
      if (!call || (call.state === 'ringing' && user === call.to)) return;
      // A short reconnect should not immediately free a live WebRTC session.
      cancel(call.disconnectTimer);
      call.disconnectTimer = later(() => {
        if (!onlineUsers.has(user)) finish(call, 'disconnected');
      }, 15000);
      call.disconnectTimer?.unref?.();
    },
    dispose() { for (const call of calls.values()) { cancel(call.timer); cancel(call.disconnectTimer); } calls.clear(); byUser.clear(); }
  };
}
module.exports = { createCallSignaling };
