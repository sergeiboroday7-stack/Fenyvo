function normalizedAddress(value) {
  if (typeof value !== 'string') return 'unknown';
  const trimmed = value.trim();
  if (!trimmed) return 'unknown';
  return trimmed.startsWith('::ffff:') ? trimmed.slice(7) : trimmed;
}

function getClientAddress(request, trustProxy = false) {
  if (trustProxy) {
    const forwarded = request?.headers?.['x-forwarded-for'];
    const first = Array.isArray(forwarded) ? forwarded[0] : forwarded;
    const address = first?.split(',')[0]?.trim();
    if (address) return normalizedAddress(address);
  }
  return normalizedAddress(request?.socket?.remoteAddress);
}

class AuthRateLimiter {
  constructor({ maxAttempts, windowMs, now = Date.now }) {
    if (!Number.isSafeInteger(maxAttempts) || maxAttempts < 1) {
      throw new Error('maxAttempts must be a positive integer');
    }
    if (!Number.isSafeInteger(windowMs) || windowMs < 1) {
      throw new Error('windowMs must be a positive integer');
    }
    this.maxAttempts = maxAttempts;
    this.windowMs = windowMs;
    this.now = now;
    this.entries = new Map();
  }

  consume(key) {
    const now = this.now();
    const safeKey = key || 'unknown';
    let entry = this.entries.get(safeKey);
    if (!entry || now >= entry.resetAt) {
      entry = { attempts: 0, resetAt: now + this.windowMs };
    }

    if (entry.attempts >= this.maxAttempts) {
      this.entries.set(safeKey, entry);
      return {
        allowed: false,
        retryAfterSeconds: Math.max(1, Math.ceil((entry.resetAt - now) / 1000)),
      };
    }

    entry.attempts += 1;
    this.entries.set(safeKey, entry);
    return { allowed: true, retryAfterSeconds: 0 };
  }

  reset(key) {
    this.entries.delete(key || 'unknown');
  }

  cleanup() {
    const now = this.now();
    for (const [key, entry] of this.entries) {
      if (now >= entry.resetAt) this.entries.delete(key);
    }
  }
}

module.exports = { AuthRateLimiter, getClientAddress, normalizedAddress };
