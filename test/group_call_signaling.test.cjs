'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createGroupCallSignaling } = require('../group_call_signaling');
const { createCallSignaling } = require('../call_signaling');
function fixture() {
  const sent = [], timers = [], busy = new Set(); let time = 100;
  const onlineUsers = new Map(['A','B','C','D','E','Out'].map(u => [u, { u }]));
  const groups = { g: { name: 'Test', members: ['A','B','C','D','E'] },
    h: { name: 'Other', members: ['A','B','C'] } };
  const api = createGroupCallSignaling({ send: (ws, type, data) => sent.push({ to: ws.u, type, data }),
    onlineUsers, getGroup: id => groups[id], getMembers: g => g?.members || [],
    isPrivateBusy: u => busy.has(u), now: () => time,
    later: (fn, ms) => { const t = { fn, ms }; timers.push(t); return t; }, cancel: t => { if (t) t.cancelled = true; } });
  const send = (u, type, data) => api.handle(onlineUsers.get(u), u, type, data);
  const joined = u => sent.findLast(x => x.to === u && x.type === 'group_call_joined').data;
  const start = (u = 'A', groupId = 'g', requestId = u) => {
    send(u, 'group_call_start', { groupId, requestId }); return joined(u);
  };
  const join = u => { send(u, 'group_call_join', { groupId: 'g', callId: joined('A').call.id, requestId: u }); return joined(u); };
  const packet = u => ({ groupId: 'g', callId: joined(u).call.id, sessionId: joined(u).sessionId });
  return { api, sent, timers, busy, onlineUsers, groups, send, start, join, joined, packet, advance: ms => { time += ms; } };
}
test('room invite is group-only and not auto-join', () => {
  const f = fixture(); const a = f.start();
  assert.equal(a.call.participants.length, 1);
  assert.deepEqual(f.sent.filter(x => x.type === 'group_call_invite').map(x => x.to), ['B','C','D','E']);
  assert.equal(f.api.isBusy('B'), false); assert.equal(f.api.isBusy('A'), true); f.api.dispose();
});
test('only authenticated current group sockets may inspect/start/join', () => {
  const f = fixture(); f.start();
  for (const type of ['group_call_start','group_call_get','group_call_join','group_call_signal']) {
    f.send('Out', type, { groupId: 'g', requestId: 'evil' }); assert.equal(f.sent.at(-1).type, 'group_call_error');
    f.api.handle({ u: 'fake' }, 'A', type, { groupId: 'g' }); assert.equal(f.sent.at(-1).type, 'group_call_error');
  }
  f.send('Out', 'group_call_sync', {}); assert.equal(f.sent.at(-1).data.calls.length, 0); f.api.dispose();
});
test('four member cap and parallel start converge on one room', () => {
  const f = fixture(); const a = f.start(); const b = f.start('B');
  assert.equal(a.call.id, b.call.id); f.join('C'); f.join('D');
  f.send('E', 'group_call_join', { groupId: 'g', callId: a.call.id, requestId: 'E' });
  assert.equal(f.sent.at(-1).type, 'group_call_error'); assert.equal(f.api.isBusy('E'), false); f.api.dispose();
});
test('creator leaving keeps other members connected; last exit closes room', () => {
  const f = fixture(); f.start(); f.join('B'); f.join('C');
  f.send('A', 'group_call_leave', f.packet('A'));
  const state = f.sent.findLast(x => x.type === 'group_call_state').data;
  assert.deepEqual(state.call.participants.map(p => p.user), ['B','C']);
  f.send('B', 'group_call_leave', f.packet('B')); f.send('C', 'group_call_leave', f.packet('C'));
  assert.equal(f.sent.at(-1).data.call, null); assert.equal(f.api.isBusy('A'), false); f.api.dispose();
});
test('late leave/ICE from previous membership cannot break rejoin', () => {
  const f = fixture(); f.start(); f.join('B'); const old = f.packet('B');
  f.send('B', 'group_call_leave', old);
  f.send('B', 'group_call_join', { groupId: 'g', callId: old.callId, requestId: 'new-B' });
  assert.notEqual(old.sessionId, f.joined('B').sessionId);
  f.send('B', 'group_call_leave', old); assert.equal(f.api.isBusy('B'), true);
  const count = f.sent.length;
  f.send('A', 'group_call_signal', { ...f.packet('A'), to: 'B', toSession: old.sessionId,
    signal: { kind: 'ice', candidate: { candidate: 'candidate' } } });
  assert.equal(f.sent.length, count); f.api.dispose();
});
test('signaling stamps sender and does not broadcast SDP', () => {
  const f = fixture(); f.start(); f.join('B'); f.join('C');
  const n = f.sent.length;
  f.send('A', 'group_call_signal', { ...f.packet('A'), from: 'Out', to: 'B', toSession: f.joined('B').sessionId,
    signal: { kind: 'offer', sdp: 'test-sdp', secret: 'ignored' } });
  assert.equal(f.sent.length, n + 1); const result = f.sent.at(-1);
  assert.equal(result.to, 'B'); assert.equal(result.data.from, 'A'); assert.equal(result.data.signal.secret, undefined);
  f.api.dispose();
});
test('lease and membership required for mute or signal', () => {
  const f = fixture(); f.start(); f.join('B');
  f.send('B', 'group_call_mute', { ...f.packet('B'), sessionId: f.joined('A').sessionId, muted: true });
  assert.equal(f.sent.at(-1).type, 'group_call_error');
  f.groups.g.members = ['A','C','D','E'];
  f.send('A', 'group_call_get', { groupId: 'g' }); assert.equal(f.api.isBusy('B'), false);
  f.api.dispose();
});
test('private busy and other group rooms cannot be joined', () => {
  const f = fixture(); f.busy.add('A');
  f.send('A', 'group_call_start', { groupId: 'g', requestId: 'r' });
  assert.equal(f.sent.at(-1).type, 'group_call_error'); f.busy.clear(); f.start();
  f.send('A', 'group_call_start', { groupId: 'h', requestId: 'second' });
  assert.equal(f.sent.at(-1).type, 'group_call_error'); f.api.dispose();
});
test('private calls respect group busy callback', () => {
  const sent = []; const users = new Map([['A', 'a'], ['B','b']]);
  const api = createCallSignaling({ send: (ws, type, data) => sent.push({ type, data }), onlineUsers: users,
    registeredUsers: { A: {}, B: {} }, push: async () => true, isExternallyBusy: u => u === 'B' });
  api.handle('a', 'A', 'call_offer', { to: 'B', callId: 'id', sdp: { type: 'offer', sdp: 'sdp' } });
  assert.equal(sent[0].data.reason, 'busy'); api.dispose();
});
test('missing heartbeat removes stale people and expired room', () => {
  const f = fixture(); f.start(); f.join('B'); f.advance(30000);
  f.send('B', 'group_call_heartbeat', f.packet('B')); f.advance(16000); f.timers[0].fn();
  assert.equal(f.api.isBusy('A'), false); assert.equal(f.api.isBusy('B'), true);
  f.api.disconnected('B'); assert.equal(f.api.isBusy('B'), false); f.api.dispose();
});
test('duplicate request is idempotent and does not reinvite', () => {
  const f = fixture(); const a = f.start(); const count = f.sent.length; const again = f.start();
  assert.equal(again.sessionId, a.sessionId); assert.equal(f.sent.length, count + 1); f.api.dispose();
});
test('replacement login does not remain busy on its obsolete socket', () => {
  const f = fixture(); f.start(); f.join('B'); const old = f.packet('B');
  f.onlineUsers.set('B', { u: 'B' });
  f.send('B', 'group_call_join', { groupId: 'g', callId: old.callId, requestId: 'replacement' });
  assert.equal(f.joined('B').requestId, 'replacement');
  assert.notEqual(f.joined('B').sessionId, old.sessionId); f.api.dispose();
});
test('malformed packets rejected; chat unaffected', () => {
  const f = fixture(); assert.equal(f.send('A', 'message', {}), false);
  for (const data of [null, [], { groupId: 'x'.repeat(200001) }]) {
    assert.equal(f.send('A', 'group_call_start', data), true); assert.equal(f.sent.at(-1).type, 'group_call_error');
  }
});
