'use strict';

function createWsFrameGuard({
  maxFrameBytes = 65536,
  maxRequests = 60,
  windowMs = 10000,
  now = Date.now,
} = {}) {
  for (const value of [maxFrameBytes, maxRequests, windowMs]) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new TypeError('Invalid WebSocket limit');
    }
  }

  if (typeof now !== 'function') {
    throw new TypeError('Invalid clock');
  }

  const sessions = new WeakMap();

  function check(socket, frame, isBinary = false) {
    if (!socket || typeof socket !== 'object') {
      return { allowed: false, reason: 'invalid_session' };
    }

    if (isBinary) {
      return { allowed: false, reason: 'binary_not_allowed' };
    }

    const validFrame =
      typeof frame === 'string' ||
      Buffer.isBuffer(frame);

    if (!validFrame) {
      return { allowed: false, reason: 'invalid_frame' };
    }

    const size = Buffer.isBuffer(frame)
      ? frame.length
      : Buffer.byteLength(frame, 'utf8');

    if (size > maxFrameBytes) {
      return { allowed: false, reason: 'frame_too_large' };
    }

    const time = now();

    if (!Number.isFinite(time)) {
      throw new TypeError('Invalid clock value');
    }

    let state = sessions.get(socket);

    if (!state) {
      state = { start: time, count: 0 };
      sessions.set(socket, state);
    }

    if (time < state.start || time - state.start >= windowMs) {
      state.start = time;
      state.count = 0;
    }

    if (state.count >= maxRequests) {
      return { allowed: false, reason: 'rate_limited' };
    }

    state.count++;

    return { allowed: true };
  }

  function revoke(socket) {
    if (socket && typeof socket === 'object') {
      sessions.delete(socket);
    }
  }

  return Object.freeze({ check, revoke });
}

module.exports = { createWsFrameGuard };