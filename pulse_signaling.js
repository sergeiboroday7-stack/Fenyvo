'use strict';

const crypto = require('node:crypto');

// FENYVO PULSE is an ephemeral rendezvous layer. It never transports WebRTC
// credentials: after two people are ready, the existing private-call protocol
// performs the actual encrypted audio/video connection.
function createPulseSignaling({
  send,
  onlineUsers,
  registeredUsers,
  isBusy = () => false,
  push = async () => false,
  now = Date.now,
  later = setTimeout,
  cancel = clearTimeout,
}) {
  const pulses = new Map();
  const byPair = new Map();
  const allowedWindows = new Set([15, 60, 240]);
  const types = new Set([
    'pulse_request',
    'pulse_accept',
    'pulse_decline',
    'pulse_cancel',
    'pulse_sync',
  ]);

  const emit = (user, type, data) => {
    const socket = onlineUsers.get(user);
    if (socket) send(socket, type, data);
  };

  const pairKey = (left, right) => [left, right].sort().join('\u0000');

  const snapshot = pulse => ({
    id: pulse.id,
    from: pulse.from,
    to: pulse.to,
    video: pulse.video,
    createdAt: pulse.createdAt,
    expiresAt: pulse.expiresAt,
    state: pulse.state,
    acceptedAt: pulse.acceptedAt || null,
    startsAt: pulse.startsAt || null,
  });

  const arm = (pulse, milliseconds, reason) => {
    cancel(pulse.timer);
    pulse.timer = later(() => close(pulse, reason), milliseconds);
    pulse.timer?.unref?.();
  };

  function close(pulse, reason) {
    if (pulses.get(pulse.id) !== pulse) return;
    pulses.delete(pulse.id);
    if (byPair.get(pulse.pair) === pulse.id) byPair.delete(pulse.pair);
    cancel(pulse.timer);
    const data = { pulseId: pulse.id, reason, pulse: snapshot(pulse) };
    emit(pulse.from, 'pulse_closed', data);
    emit(pulse.to, 'pulse_closed', data);
  }

  function tryMatch(pulse) {
    if (pulses.get(pulse.id) !== pulse || !pulse.accepted) return;
    if (!onlineUsers.has(pulse.from) || !onlineUsers.has(pulse.to)) {
      emit(pulse.to, 'pulse_waiting', {
        pulse: snapshot(pulse),
        reason: 'Ждём, когда собеседник появится в сети',
      });
      return;
    }
    if (isBusy(pulse.from) || isBusy(pulse.to)) {
      const data = {
        pulse: snapshot(pulse),
        reason: 'Звонок начнётся, когда активный разговор завершится',
      };
      emit(pulse.from, 'pulse_waiting', data);
      emit(pulse.to, 'pulse_waiting', data);
      return;
    }
    pulse.state = 'matched';
    pulse.startsAt = now() + 4000;
    const data = { pulse: snapshot(pulse), startsAt: pulse.startsAt };
    emit(pulse.from, 'pulse_match', data);
    emit(pulse.to, 'pulse_match', data);
    arm(pulse, 16000, 'started');
  }

  function sendState(pulse, invite = false) {
    emit(pulse.from, 'pulse_state', { pulse: snapshot(pulse) });
    emit(pulse.to, invite ? 'pulse_invite' : 'pulse_state', {
      pulse: snapshot(pulse),
    });
  }

  function fail(ws, requestId, reason) {
    send(ws, 'pulse_error', { requestId, reason });
  }

  function handle(ws, user, type, rawData = {}) {
    if (!types.has(type)) return false;
    const data = rawData && typeof rawData === 'object' && !Array.isArray(rawData)
      ? rawData
      : {};
    const requestId = String(data.requestId || '').trim().slice(0, 100);
    if (!user || onlineUsers.get(user) !== ws) {
      fail(ws, requestId, 'Сначала необходимо войти');
      return true;
    }
    if (JSON.stringify(data).length > 4096) {
      fail(ws, requestId, 'Слишком большой пакет FENYVO PULSE');
      return true;
    }

    if (type === 'pulse_sync') {
      const mine = [...pulses.values()]
        .filter(pulse => pulse.from === user || pulse.to === user)
        .map(snapshot);
      send(ws, 'pulse_sync', { pulses: mine, serverTime: now() });
      for (const pulse of pulses.values()) {
        if ((pulse.from === user || pulse.to === user) && pulse.accepted) {
          tryMatch(pulse);
        }
      }
      return true;
    }

    if (type === 'pulse_request') {
      const to = String(data.to || '').trim();
      if (!to || to === user || !Object.prototype.hasOwnProperty.call(registeredUsers, to)) {
        fail(ws, requestId, 'Некорректный получатель FENYVO PULSE');
        return true;
      }
      if (isBusy(user) || isBusy(to)) {
        fail(ws, requestId, 'Сейчас один из участников уже разговаривает');
        return true;
      }
      const pair = pairKey(user, to);
      const existing = pulses.get(byPair.get(pair));
      const requestedVideo = data.video === true;
      const requestedWindow = Number(data.windowMinutes);
      const windowMinutes = allowedWindows.has(requestedWindow)
        ? requestedWindow
        : 60;

      if (existing) {
        if (existing.state === 'matched') {
          fail(ws, requestId, 'FENYVO PULSE уже соединил вас');
          return true;
        }
        if (existing.from === to && existing.to === user) {
          existing.video = existing.video && requestedVideo;
          existing.accepted = true;
          existing.acceptedAt = now();
          existing.state = 'accepted';
          sendState(existing);
          tryMatch(existing);
          return true;
        }
        existing.video = requestedVideo;
        existing.expiresAt = now() + windowMinutes * 60000;
        existing.state = 'pending';
        existing.accepted = false;
        existing.acceptedAt = null;
        existing.startsAt = null;
        arm(existing, windowMinutes * 60000, 'expired');
        sendState(existing, true);
        void Promise.resolve(push(to, snapshot(existing))).catch(() => {});
        return true;
      }

      const pulseCount = [...pulses.values()].filter(
        pulse => pulse.from === user || pulse.to === user,
      ).length;
      if (pulseCount >= 5) {
        fail(ws, requestId, 'Слишком много активных приглашений FENYVO PULSE');
        return true;
      }

      const createdAt = now();
      const pulse = {
        id: crypto.randomUUID(),
        pair,
        from: user,
        to,
        video: requestedVideo,
        createdAt,
        expiresAt: createdAt + windowMinutes * 60000,
        state: 'pending',
        accepted: false,
        acceptedAt: null,
        startsAt: null,
        timer: null,
      };
      pulses.set(pulse.id, pulse);
      byPair.set(pair, pulse.id);
      arm(pulse, windowMinutes * 60000, 'expired');
      sendState(pulse, true);
      void Promise.resolve(push(to, snapshot(pulse))).catch(() => {});
      return true;
    }

    const id = String(data.pulseId || '').trim();
    const pulse = pulses.get(id);
    if (!pulse || (pulse.from !== user && pulse.to !== user)) {
      fail(ws, requestId, 'FENYVO PULSE уже завершён');
      return true;
    }

    if (type === 'pulse_accept') {
      if (pulse.to !== user || pulse.state === 'matched') {
        fail(ws, requestId, 'Это приглашение нельзя принять');
        return true;
      }
      pulse.accepted = true;
      pulse.acceptedAt = now();
      pulse.state = 'accepted';
      sendState(pulse);
      tryMatch(pulse);
      return true;
    }

    if (type === 'pulse_decline') {
      if (pulse.to !== user) {
        fail(ws, requestId, 'Отклонить приглашение может только получатель');
      } else {
        close(pulse, 'declined');
      }
      return true;
    }

    close(pulse, 'cancelled');
    return true;
  }

  return {
    handle,
    isReserved: user => [...pulses.values()].some(
      pulse => pulse.state === 'matched' && (pulse.from === user || pulse.to === user),
    ),
    dispose() {
      for (const pulse of pulses.values()) cancel(pulse.timer);
      pulses.clear();
      byPair.clear();
    },
  };
}

module.exports = { createPulseSignaling };
