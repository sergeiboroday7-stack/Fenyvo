'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createCallSignaling } = require('../call_signaling');
function fixture() {
  const sent = [], pushes = [], timers = [];
  let now = 1000;
  const onlineUsers = new Map([['Alice', 'a'], ['Bob', 'b'], ['Eve', 'e']]);
  const api = createCallSignaling({
    send: (ws, type, data) => sent.push({ ws, type, data }), onlineUsers,
    registeredUsers: { Alice: {}, Bob: {}, Eve: {} },
    push: async (to, data) => { pushes.push({ to, data }); return true; },
    now: () => now, later: (fn, ms) => { const t = { fn, ms }; timers.push(t); return t; },
    cancel: t => { if (t) t.cancelled = true; }
  });
  const send = (user, type, data) => api.handle(onlineUsers.get(user), user, type, data);
  const offer = (id = 'id', to = 'Bob') => send('Alice', 'call_offer', {
    to, callId: id, from: 'Impostor', video: true, sdp: { type: 'offer', sdp: 'valid-sdp' }
  });
  return { api, sent, pushes, timers, onlineUsers, send, offer, advance: n => { now += n; } };
}
test('offer stamps identity and keeps SDP out of push', () => {
  const f = fixture(); f.offer();
  assert.equal(f.sent[0].data.from, 'Alice'); assert.equal(f.sent[0].ws, 'b');
  assert.equal(f.pushes[0].data.sdp, undefined);
  assert.match(f.pushes[0].data.callToken, /^[0-9a-f]{64}$/); f.api.dispose();
});
test('offline phone retains SDP and ICE until authenticated replay', () => {
  const f = fixture(); f.onlineUsers.delete('Bob'); f.offer();
  f.send('Alice', 'call_ice_candidate', { to: 'Bob', callId: 'id', candidate: { candidate: 'ice' } });
  assert.equal(f.sent.length, 0); assert.equal(f.pushes.length, 1);
  f.onlineUsers.set('Bob', 'new-b'); f.send('Bob', 'get_pending_call', {});
  assert.deepEqual(f.sent.map(x => x.type), ['call_offer', 'call_ice_candidate']);
  assert.ok(f.sent.every(x => x.ws === 'new-b')); f.api.dispose();
});
test('outsider cannot fetch or end a call', () => {
  const f = fixture(); f.offer(); f.sent.length = 0;
  f.send('Eve', 'get_pending_call', {});
  f.send('Eve', 'call_end', { to: 'Bob', callId: 'id' });
  assert.deepEqual(f.sent.map(x => x.type), ['pending_call_empty', 'call_error']);
  assert.ok(f.sent.every(x => x.ws === 'e')); f.api.dispose();
});
test('unauthenticated and replaced sockets denied', () => {
  const f = fixture();
  for (const user of [null, 'Alice']) f.api.handle('wrong', user, 'call_offer', {});
  assert.ok(f.sent.every(x => x.type === 'call_error')); assert.equal(f.pushes.length, 0);
});
test('busy callee does not get second invitation', () => {
  const f = fixture(); f.offer(); f.offer('second');
  assert.equal(f.sent.at(-1).type, 'call_reject'); assert.equal(f.sent.at(-1).data.reason, 'busy');
  assert.equal(f.pushes.length, 1); f.api.dispose();
});
test('caller cancel removes pending call and pushes cancellation', () => {
  const f = fixture(); f.offer(); f.send('Alice', 'call_end', { to: 'Bob', callId: 'id' });
  assert.equal(f.pushes.at(-1).data.type, 'call_cancel');
  f.send('Bob', 'get_pending_call', {}); assert.equal(f.sent.at(-1).type, 'pending_call_empty');
  f.offer('new'); assert.equal(f.sent.at(-1).type, 'call_offer'); f.api.dispose();
});
test('capability can only decline its own ringing call', () => {
  const f = fixture(); f.offer(); const token = f.pushes[0].data.callToken;
  assert.equal(f.api.decline('id', 'a'.repeat(64)), false);
  assert.equal(f.api.authorize('id', 'я'.repeat(64)), null);
  assert.equal(f.api.decline('other', token), false);
  assert.equal(f.api.decline('id', token), true);
  assert.equal(f.api.decline('id', token), false);
});
test('expiry prevents delayed push from ringing', () => {
  const f = fixture(); f.offer(); const token = f.pushes[0].data.callToken;
  f.advance(75001); assert.equal(f.api.authorize('id', token), null);
  f.send('Bob', 'get_pending_call', {}); assert.equal(f.sent.at(-1).type, 'pending_call_empty'); f.api.dispose();
});
test('timeout frees participants', () => {
  const f = fixture(); f.offer(); f.timers[0].fn();
  assert.equal(f.pushes.at(-1).data.type, 'call_cancel');
  f.offer('new'); assert.equal(f.sent.at(-1).type, 'call_offer'); f.api.dispose();
});
test('answer only from callee; answered call revokes decline token', () => {
  const f = fixture(); f.offer(); const token = f.pushes[0].data.callToken;
  f.send('Alice', 'call_answer', { to: 'Bob', callId: 'id', sdp: { type: 'answer', sdp: 'ok' } });
  assert.equal(f.sent.at(-1).type, 'call_error');
  f.send('Bob', 'call_answer', { to: 'Alice', callId: 'id', sdp: { type: 'answer', sdp: 'ok' } });
  assert.equal(f.sent.at(-1).ws, 'a'); assert.equal(f.sent.at(-1).type, 'call_answer');
  assert.equal(f.api.decline('id', token), false);
  f.send('Alice', 'call_connected', { to: 'Bob', callId: 'id' });
  assert.equal(f.timers.at(-1).cancelled, true); f.api.dispose();
});
test('invalid recipients and oversized/malformed SDP rejected', () => {
  for (const data of [{ to: '__proto__' }, { to: 'Alice' }, { to: 'Unknown' },
    { callId: 'x'.repeat(101) }, { sdp: { type: 'answer', sdp: 'x' } },
    { sdp: { type: 'offer', sdp: 'x'.repeat(200001) } }]) {
    const f = fixture(); f.send('Alice', 'call_offer', { to: 'Bob', callId: 'id', ...data });
    assert.equal(f.sent[0].type, 'call_error'); assert.equal(f.pushes.length, 0);
  }
});
test('ordinary chat traffic not intercepted', () => {
  const f = fixture(); assert.equal(f.send('Alice', 'message', {}), false);
});
test('encrypted call signaling is relayed without plaintext SDP or ICE', () => {
  const f = fixture();
  const encrypted = { e2ee: true, e2eeVersion: 2, e2eeProtocol: 'signal',
    cipherType: 3, ciphertext: 'opaque-ciphertext' };
  f.send('Alice', 'call_offer', {
    to: 'Bob', callId: 'secure', video: true, e2eeCall: encrypted
  });
  assert.deepEqual(f.sent[0].data.e2eeCall, encrypted);
  assert.equal(f.sent[0].data.sdp, undefined);
  f.send('Alice', 'call_ice_candidate', {
    to: 'Bob', callId: 'secure', e2eeCall: encrypted
  });
  assert.deepEqual(f.sent.at(-1).data.e2eeCall, encrypted);
  assert.equal(f.sent.at(-1).data.candidate, undefined);
  f.send('Bob', 'call_answer', {
    to: 'Alice', callId: 'secure', e2eeCall: encrypted
  });
  assert.deepEqual(f.sent.at(-1).data.e2eeCall, encrypted);
  assert.equal(f.sent.at(-1).data.sdp, undefined);
  f.api.dispose();
});
test('callee suspension keeps ringing; caller disconnect cancels', () => {
  const f = fixture(); f.offer(); const count = f.timers.length;
  f.onlineUsers.delete('Bob'); f.api.disconnected('Bob'); assert.equal(f.timers.length, count);
  f.onlineUsers.delete('Alice'); f.api.disconnected('Alice'); f.timers.at(-1).fn();
  assert.equal(f.pushes.at(-1).data.type, 'call_cancel');
});
