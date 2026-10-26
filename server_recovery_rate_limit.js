'use strict';

const { AuthRateLimiter } = require('./server_security');

function createRecoveryRateLimiter() {
  const accountLimiter = new AuthRateLimiter({ maxAttempts: 5, windowMs: 900000 });
  const ipLimiter = new AuthRateLimiter({ maxAttempts: 30, windowMs: 900000 });

  function consume(username, ipAddress) {
    if (typeof username !== 'string' || !username.trim()) throw new TypeError('Invalid account identifier');
    if (typeof ipAddress !== 'string' || !ipAddress.trim()) throw new TypeError('Invalid IP address');
    const account = username.trim().toLowerCase();
    const ip = ipAddress.trim();
    const a = accountLimiter.consume(account);
    const b = ipLimiter.consume(ip);
    return { allowed: a.allowed && b.allowed, retryAfterSeconds: Math.max(a.retryAfterSeconds, b.retryAfterSeconds) };
  }

  return Object.freeze({ consume });
}

module.exports = { createRecoveryRateLimiter };
