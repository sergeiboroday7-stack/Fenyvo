'use strict';

const { randomBytes } = require('node:crypto');

// In-memory, short-lived consent requests. A server restart cancels unapproved
// joins (fail closed). Only the authenticated owner socket may decide.
class TemporaryJoinApproval {
  constructor({ ttlMs = 90_000, maxPending = 256, now = () => Date.now() } = {}) {
    this.ttlMs = ttlMs;
    this.maxPending = maxPending;
    this.now = now;
    this.byId = new Map();
    this.byToken = new Map();
  }

  cleanup() {
    const time = this.now();
    for (const request of this.byId.values()) {
      if (request.expiresAt <= time) this._drop(request);
    }
  }

  _drop(request) {
    if (this.byId.get(request.requestId) === request) this.byId.delete(request.requestId);
    if (this.byToken.get(request.token) === request) this.byToken.delete(request.token);
  }

  request({ token, owner, guest, ownerSocket, guestSocket }) {
    this.cleanup();
    if (!/^[a-f0-9]{64}$/.test(token) ||
        typeof owner !== 'string' || !owner.trim() ||
        typeof guest !== 'string' || !guest.trim() ||
        owner.toLowerCase() === guest.toLowerCase() ||
        !ownerSocket || !guestSocket) {
      return { ok: false, reason: 'Некорректный запрос подключения' };
    }
    const existing = this.byToken.get(token);
    if (existing) {
      if (existing.guest.toLowerCase() === guest.toLowerCase() &&
          existing.ownerSocket === ownerSocket && existing.guestSocket === guestSocket) {
        return { ok: true, repeated: true, requestId: existing.requestId,
          expiresAt: existing.expiresAt };
      }
      return { ok: false, reason: 'По этому приглашению уже ожидают подтверждения' };
    }
    if (this.byId.size >= this.maxPending) {
      return { ok: false, reason: 'Слишком много ожидающих запросов' };
    }
    const requestId = randomBytes(16).toString('hex');
    const request = {
      requestId, token, owner, guest, ownerSocket, guestSocket,
      expiresAt: this.now() + this.ttlMs,
    };
    this.byId.set(requestId, request);
    this.byToken.set(token, request);
    return { ok: true, repeated: false, requestId, expiresAt: request.expiresAt };
  }

  // The owner can recover a missed approval while the same socket and
  // authenticated account remain valid. No guest identity is disclosed.
  pendingForOwner({ owner, ownerSocket }) {
    this.cleanup();
    if (typeof owner !== 'string' || !owner.trim() || !ownerSocket) return [];
    return Array.from(this.byId.values())
      .filter((r) => r.owner.toLowerCase() === owner.toLowerCase() &&
        r.ownerSocket === ownerSocket)
      .map((r) => ({ token: r.token, requestId: r.requestId,
        expiresAt: new Date(r.expiresAt).toISOString() }));
  }

  takeDecision({ requestId, owner, ownerSocket }) {
    this.cleanup();
    const request = this.byId.get(requestId);
    if (!request || typeof owner !== 'string' ||
        request.owner.toLowerCase() !== owner.toLowerCase() ||
        request.ownerSocket !== ownerSocket) {
      return { ok: false, reason: 'Запрос недоступен или истёк' };
    }
    this._drop(request); // one time; repeated decisions are rejected
    return { ok: true, request };
  }
}

module.exports = { TemporaryJoinApproval };
