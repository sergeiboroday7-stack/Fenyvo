'use strict';

function revokeRecoverySession(username, onlineUsers, mediaTokens, send) {
  if (typeof username !== 'string' || !username.trim()) return false;
  if (!onlineUsers || typeof onlineUsers.get !== 'function' || typeof onlineUsers.delete !== 'function') throw new TypeError('Invalid online users store');
  if (!mediaTokens || typeof mediaTokens.delete !== 'function') throw new TypeError('Invalid media token store');
  if (typeof send !== 'function') throw new TypeError('Invalid send function');
  const ws = onlineUsers.get(username);
  if (!ws) return false;
  onlineUsers.delete(username);
  if (ws.__mediaToken) {
    mediaTokens.delete(ws.__mediaToken);
    ws.__mediaToken = null;
  }
  try { send(ws, 'disconnected', { reason: 'Пароль аккаунта восстановлен. Войдите заново.' }); } catch (_) {}
  try { ws.close(1000, 'Account recovery'); } catch (_) {}
  return true;
}

module.exports = { revokeRecoverySession };
