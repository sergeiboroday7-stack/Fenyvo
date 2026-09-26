'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createGroupCallSignaling } = require('../group_call_signaling');
const { createCallSignaling } = require('../call_signaling');
function fixture() {
  const sent = [], timers = [], notifications = [], busy = new Set(); let time = 100;
  const onlineUsers = new Map(['A','B','C','D','E','Out'].map(u => [u, { u }]));
  const groups = { g: { name: 'Test', members: ['A','B','C','D','E'] },
    h: { name: 'Other', members: ['A','B','C'] } };
  const api = createGroupCallSignaling({ send: (ws, type, data) => sent.push({ to: ws.u, type, data }),
    onlineUsers, getGroup: id => groups[id], getMembers: g => g?.members || [],
    isPrivateBusy: u => busy.has(u), now: () => time,
    notifyStarted: (user, room) => notifications.push({ user, room }),
    later: (fn, ms) => { const t = { fn, ms }; timers.push(t); return t; }, cancel: t => { if (t) t.cancelled = true; } });
  const send = (u, type, data) => api.handle(onlineUsers.get(u), u, type, data);
  const joined = u => sent.findLast(x => x.to === u && x.type === 'group_call_joined').data;
  const start = (u = 'A', groupId = 'g', requestId = u) => {
    send(u, 'group_call_start', { groupId, requestId }); return joined(u);
  };
  const join = u => {
    const callId = joined('A').call.id;
    send(u, 'group_call_join_request', { groupId: 'g', callId });
    send('A', 'group_call_join_response', { groupId: 'g', callId, target: u, accepted: true });
    send(u, 'group_call_join', { groupId: 'g', callId, requestId: u });
    return joined(u);
  };
  const watch = u => {
    const callId = joined('A').call.id;
    send(u, 'group_call_watch', { groupId: 'g', callId, requestId: `watch-${u}` });
    return sent.findLast(x => x.to === u && x.type === 'group_call_watching').data;
  };
  const packet = u => ({ groupId: 'g', callId: joined(u).call.id, sessionId: joined(u).sessionId });
  return { api, sent, timers, notifications, busy, onlineUsers, groups, send, start, join, watch, joined, packet, advance: ms => { time += ms; } };
}
test('viewers watch without occupying one of four stage places', () => {
  const f = fixture(); f.start(); f.join('B'); f.join('C'); f.join('D');
  const viewer = f.watch('E');
  assert.equal(viewer.call.participants.find(p => p.user === 'E').role, 'viewer');
  assert.equal(viewer.call.participants.filter(p => p.role !== 'viewer').length, 4);
  assert.deepEqual(f.api.activeUsers('g', viewer.call.id), ['A', 'B', 'C', 'D', 'E']);
  f.api.dispose();
});
test('host departure waits for an appointed moderator to accept hosting', () => {
  const f = fixture(); f.start(); f.join('B');
  f.send('A', 'group_call_moderate', {
    ...f.packet('A'), target: 'B', action: 'promote',
  });
  f.send('A', 'group_call_leave', f.packet('A'));

  const state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, '');
  assert.equal(state.awaitingHost, true);
  assert.equal(state.participants.find(p => p.user === 'B').role, 'moderator');
  assert.equal(state.hostGraceUntil, 300100);
  assert.equal(f.api.isBusy('B'), true);
  const shutdown = f.timers.findLast(
    t => t.ms === 5 * 60 * 1000 && !t.cancelled,
  );
  assert.ok(shutdown);

  f.send('B', 'group_call_take_host', f.packet('B'));
  const continued = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(continued.startedBy, 'B');
  assert.equal(continued.awaitingHost, false);
  assert.equal(continued.participants.find(p => p.user === 'B').role, 'host');
  assert.equal(shutdown.cancelled, true);
  f.api.dispose();
});
test('waiting call ends after five minutes when nobody accepts hosting', () => {
  const f = fixture(); const started = f.start(); f.join('B');
  f.send('A', 'group_call_leave', f.packet('A'));
  const shutdown = f.timers.findLast(
    t => t.ms === 5 * 60 * 1000 && !t.cancelled,
  );
  assert.ok(shutdown);
  f.advance(5 * 60 * 1000);
  shutdown.fn();
  assert.deepEqual(f.api.activeUsers('g', started.call.id), []);
  assert.equal(f.api.isBusy('B'), false);
  assert.equal(
    f.sent.findLast(x => x.to === 'B' && x.type === 'group_call_left').data.reason,
    'Ведущий или модератор не вернулся вовремя',
  );
  f.api.dispose();
});
test('explicit owner exit ends the call for everyone immediately', () => {
  const f = fixture(); const started = f.start(); f.join('B'); f.watch('C');
  f.send('A', 'group_call_leave', { ...f.packet('A'), endForAll: true });
  assert.deepEqual(f.api.activeUsers('g', started.call.id), []);
  assert.equal(f.api.isBusy('B'), false);
  assert.equal(f.api.isBusy('C'), false);
  assert.equal(
    f.sent.findLast(x => x.to === 'B' && x.type === 'group_call_left').data.reason,
    'Автор завершил групповой звонок',
  );
  assert.equal(
    f.timers.some(t => t.ms === 5 * 60 * 1000 && !t.cancelled),
    false,
  );
  f.api.dispose();
});
test('minimized owner starts grace timer and returning owner cancels it', () => {
  const f = fixture(); f.start(); f.join('B');
  f.send('A', 'group_call_presence', { ...f.packet('A'), away: true });
  let state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(state.awaitingHost, true);
  assert.equal(state.participants.find(p => p.user === 'A').away, true);
  const shutdown = f.timers.findLast(
    t => t.ms === 5 * 60 * 1000 && !t.cancelled,
  );
  assert.ok(shutdown);

  f.send('A', 'group_call_presence', { ...f.packet('A'), away: false });
  state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(state.startedBy, 'A');
  assert.equal(state.awaitingHost, false);
  assert.equal(state.participants.find(p => p.user === 'A').away, false);
  assert.equal(shutdown.cancelled, true);
  f.api.dispose();
});

test('owner returns directly and automatically reclaims hosting', () => {
  const f = fixture();
  const started = f.start();
  f.join('B');
  f.send('A', 'group_call_leave', f.packet('A'));

  f.send('A', 'group_call_join', {
    groupId: 'g', callId: started.call.id, requestId: 'return-A-direct',
  });

  const state = f.joined('A').call;
  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, 'A');
  assert.equal(state.hostGraceUntil, null);
  assert.equal(state.participants.find(p => p.user === 'A').role, 'host');
  assert.equal(state.participants.find(p => p.user === 'B').role, 'guest');
  assert.equal(state.awaitingHost, false);
  assert.equal(f.api.isBusy('A'), true);
  f.api.dispose();
});

test('moderator can reconnect during owner grace and take host role', () => {
  const f = fixture();
  const started = f.start();
  f.join('B');

  f.send('A', 'group_call_moderate', {
    ...f.packet('A'),
    target: 'B',
    action: 'promote',
  });

  f.api.disconnected('A');

  let state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;

  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, '');
  assert.equal(state.awaitingHost, true);
  assert.equal(
    state.participants.find(p => p.user === 'B').role,
    'moderator',
  );

  const shutdown = f.timers.findLast(
    t => t.ms === 5 * 60 * 1000 && !t.cancelled,
  );
  assert.ok(shutdown);

  f.api.disconnected('B');

  assert.equal(f.api.isBusy('B'), false);

  f.onlineUsers.set('B', { u: 'B' });

  f.send('B', 'group_call_join_request', {
    groupId: 'g',
    callId: started.call.id,
  });

  const approval = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_join_response',
  );

  assert.equal(approval.data.accepted, true);

  f.send('B', 'group_call_join', {
    groupId: 'g',
    callId: started.call.id,
    requestId: 'moderator-return-B',
  });

  state = f.joined('B').call;

  assert.equal(
    state.participants.find(p => p.user === 'B').role,
    'moderator',
  );
  assert.equal(state.awaitingHost, true);

  f.send('B', 'group_call_take_host', f.packet('B'));

  state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;

  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, 'B');
  assert.equal(state.awaitingHost, false);
  assert.equal(
    state.participants.find(p => p.user === 'B').role,
    'host',
  );
  assert.equal(shutdown.cancelled, true);
  assert.equal(f.api.isBusy('B'), true);

  f.api.dispose();
});
test('moderator temporarily hosts and owner regains host after returning', () => {
  const f = fixture();
  const started = f.start();
  f.join('B');

  f.send('A', 'group_call_moderate', {
    ...f.packet('A'), target: 'B', action: 'promote',
  });
  f.send('A', 'group_call_leave', f.packet('A'));

  let state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, '');
  assert.equal(state.awaitingHost, true);
  assert.equal(state.participants.find(p => p.user === 'B').role, 'moderator');
  assert.equal(state.hostGraceUntil, 300100);

  f.send('B', 'group_call_take_host', f.packet('B'));
  state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(state.startedBy, 'B');
  assert.equal(state.awaitingHost, false);

  const callId = started.call.id;
  f.send('A', 'group_call_join_request', { groupId: 'g', callId });
  f.send('B', 'group_call_join_response', {
    groupId: 'g', callId, target: 'A', accepted: true,
  });
  f.send('A', 'group_call_join', {
    groupId: 'g', callId, requestId: 'return-A',
  });

  state = f.joined('A').call;
  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, 'A');
  assert.equal(state.participants.find(p => p.user === 'A').role, 'host');
  assert.equal(state.participants.find(p => p.user === 'B').role, 'moderator');
  assert.equal(state.hostGraceUntil, null);
  f.api.dispose();
});
test('featured participant selection is broadcast to every group member', () => {
  const f = fixture(); f.start(); f.join('B');
  f.send('A', 'group_call_feature', { ...f.packet('A'), target: 'B' });
  const states = f.sent.filter(x => x.type === 'group_call_state');
  assert.equal(states.at(-1).data.call.featuredUser, 'B');
  assert.ok(states.some(x => x.to === 'A' && x.data.call.featuredUser === 'B'));
  assert.ok(states.some(x => x.to === 'B' && x.data.call.featuredUser === 'B'));
  f.api.dispose();
});
test('only host or moderator can pin a call message', () => {
  const f = fixture(); f.start(); f.join('B');
  const message = { id: 'm1', from: 'B', text: 'Важно' };

  f.send('B', 'group_call_pin', { ...f.packet('B'), message });
  assert.equal(f.sent.at(-1).type, 'group_call_error');

  let viewer = f.watch('C');
  assert.equal(viewer.call.pinnedMessage, null);

  f.send('A', 'group_call_moderate', {
    ...f.packet('A'), target: 'B', action: 'promote',
  });
  f.send('B', 'group_call_pin', { ...f.packet('B'), message });

  let state = f.sent.findLast(
    x => x.to === 'C' && x.type === 'group_call_state',
  ).data.call;
  assert.deepEqual(state.pinnedMessage, message);

  viewer = f.watch('D');
  assert.deepEqual(viewer.call.pinnedMessage, message);

  f.send('A', 'group_call_pin', { ...f.packet('A'), message: null });

  state = f.sent.findLast(
    x => x.to === 'C' && x.type === 'group_call_state',
  ).data.call;
  assert.equal(state.pinnedMessage, null);
  f.api.dispose();
});
test('host can invite a viewer to stage but an ordinary guest cannot', () => {
  const f = fixture(); f.start(); f.join('B'); const viewer = f.watch('C');
  f.send('B', 'group_call_stage_invite', { ...f.packet('B'), target: 'C' });
  assert.equal(f.sent.at(-1).type, 'group_call_error');
  f.send('A', 'group_call_stage_invite', { ...f.packet('A'), target: 'C' });
  const invite = f.sent.findLast(x => x.to === 'C' && x.type === 'group_call_stage_invite');
  assert.equal(invite.data.by, 'A');
  f.send('C', 'group_call_unwatch', {
    groupId: 'g', callId: viewer.call.id, sessionId: viewer.sessionId, forStage: true,
  });
  f.send('C', 'group_call_join', {
    groupId: 'g', callId: viewer.call.id, requestId: 'stage-C',
  });
  assert.equal(f.joined('C').call.participants.find(p => p.user === 'C').role, 'guest');
  f.api.dispose();
});
test('room is visible to group but does not ring or auto-join everyone', () => {
  const f = fixture(); const a = f.start();
  assert.equal(a.call.participants.length, 1);
  assert.deepEqual(f.sent.filter(x => x.type === 'group_call_invite').map(x => x.to), []);
  assert.deepEqual(f.notifications.map(x => x.user), ['B','C','D','E']);
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
  const f = fixture(); const a = f.start(); f.join('B'); f.join('C'); f.join('D');
  f.send('E', 'group_call_join', { groupId: 'g', callId: a.call.id, requestId: 'E' });
  assert.equal(f.sent.at(-1).type, 'group_call_error'); assert.equal(f.api.isBusy('E'), false); f.api.dispose();
});
test('owner network disconnect starts grace and owner can return directly', () => {
  const f = fixture();
  const started = f.start();
  f.join('B');

  f.api.disconnected('A');

  let state = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_state',
  ).data.call;

  assert.ok(state);
  assert.equal(state.owner, 'A');
  assert.equal(state.startedBy, '');
  assert.equal(state.awaitingHost, true);
  assert.deepEqual(state.participants.map(p => p.user), ['B']);
  assert.equal(f.api.isBusy('A'), false);
  assert.equal(f.api.isBusy('B'), true);

  const shutdown = f.timers.findLast(
    t => t.ms === 5 * 60 * 1000 && !t.cancelled,
  );
  assert.ok(shutdown);

  f.onlineUsers.set('A', { u: 'A' });

  f.send('A', 'group_call_join_request', {
    groupId: 'g',
    callId: started.call.id,
  });

  const approval = f.sent.findLast(
    x => x.to === 'A' && x.type === 'group_call_join_response',
  );
  assert.equal(approval.data.accepted, true);

  f.send('A', 'group_call_join', {
    groupId: 'g',
    callId: started.call.id,
    requestId: 'network-return-A',
  });

  const returned = f.joined('A');

  assert.equal(returned.requestId, 'network-return-A');
  assert.equal(returned.call.owner, 'A');
  assert.equal(returned.call.startedBy, 'A');
  assert.equal(returned.call.awaitingHost, false);
  assert.equal(f.api.isBusy('A'), true);
  assert.equal(f.api.isBusy('B'), true);
  assert.equal(shutdown.cancelled, true);

  f.api.dispose();
});
test('unexpected owner departure keeps room alive through grace even when everyone else leaves', () => {
  const f = fixture(); f.start(); f.join('B'); f.join('C');
  f.send('A', 'group_call_leave', f.packet('A'));
  let state = f.sent.findLast(x => x.type === 'group_call_state').data.call;
  assert.deepEqual(state.participants.map(p => p.user), ['B','C']);

  f.send('B', 'group_call_leave', f.packet('B'));
  f.send('C', 'group_call_leave', f.packet('C'));

  state = f.sent.findLast(x => x.type === 'group_call_state').data.call;
  assert.ok(state);
  assert.equal(state.awaitingHost, true);
  assert.deepEqual(state.participants, []);

  const shutdown = f.timers.findLast(
    t => t.ms === 5 * 60 * 1000 && !t.cancelled,
  );
  assert.ok(shutdown);

  f.advance(5 * 60 * 1000);
  shutdown.fn();

  assert.equal(
    f.sent.findLast(x => x.type === 'group_call_state').data.call,
    null,
  );
  assert.equal(f.api.isBusy('A'), false);
  assert.equal(f.api.isBusy('B'), false);
  assert.equal(f.api.isBusy('C'), false);
  f.api.dispose();
});
test('late leave/ICE from previous membership cannot break rejoin', () => {
  const f = fixture(); f.start(); f.join('B'); const old = f.packet('B');
  f.send('B', 'group_call_leave', old);
  f.send('B', 'group_call_join_request', { groupId: 'g', callId: old.callId });
  f.send('A', 'group_call_join_response', { groupId: 'g', callId: old.callId, target: 'B', accepted: true });
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
test('host can moderate guests; guests cannot moderate host', () => {
  const f = fixture(); f.start(); f.join('B');
  f.send('B', 'group_call_moderate', { ...f.packet('B'), target: 'A', action: 'kick' });
  assert.equal(f.sent.at(-1).type, 'group_call_error');
  f.send('A', 'group_call_moderate', { ...f.packet('A'), target: 'B', action: 'video_off' });
  assert.equal(f.sent.some(x => x.to === 'B' && x.type === 'group_call_moderation' && x.data.action === 'video_off'), true);
  assert.equal(f.sent.findLast(x => x.type === 'group_call_state').data.call.participants.find(x => x.user === 'B').videoEnabled, false);
  f.send('A', 'group_call_moderate', { ...f.packet('A'), target: 'B', action: 'promote' });
  assert.equal(f.sent.findLast(x => x.type === 'group_call_state').data.call.participants.find(x => x.user === 'B').role, 'moderator');
  f.send('B', 'group_call_moderate', { ...f.packet('B'), target: 'A', action: 'mute' });
  assert.notEqual(f.sent.at(-1).type, 'group_call_moderation');
  f.send('A', 'group_call_moderate', { ...f.packet('A'), target: 'B', action: 'kick' });
  assert.equal(f.api.isBusy('B'), false); f.api.dispose();
});
test('private busy and other group rooms cannot be joined', () => {
  const f = fixture(); f.busy.add('A');
  f.send('A', 'group_call_start', { groupId: 'g', requestId: 'r' });
  assert.equal(f.sent.at(-1).type, 'group_call_error'); f.busy.clear(); f.start();
  f.send('A', 'group_call_start', { groupId: 'h', requestId: 'second' });
  assert.equal(f.sent.at(-1).type, 'group_call_error'); f.api.dispose();
});
test('private caller must leave its group before inviting a group participant', () => {
  const sent = []; const users = new Map([['A', 'a'], ['B','b']]);
  const busy = new Set(['A']);
  const api = createCallSignaling({ send: (ws, type, data) => sent.push({ type, data }), onlineUsers: users,
    registeredUsers: { A: {}, B: {} }, push: async () => true, isExternallyBusy: u => busy.has(u) });
  api.handle('a', 'A', 'call_offer', { to: 'B', callId: 'id', sdp: { type: 'offer', sdp: 'sdp' } });
  assert.equal(sent[0].data.reason, 'busy');
  busy.clear(); busy.add('B'); sent.length = 0;
  api.handle('a', 'A', 'call_offer', { to: 'B', callId: 'id2', sdp: { type: 'offer', sdp: 'sdp' } });
  assert.equal(sent[0].type, 'call_offer'); api.dispose();
});
test('missing heartbeat removes stale people and expired room', () => {
  const f = fixture(); f.start(); f.join('B'); f.advance(30000);
  f.send('B', 'group_call_heartbeat', f.packet('B')); f.advance(16000); f.timers[0].fn();
  assert.equal(f.api.isBusy('A'), false); assert.equal(f.api.isBusy('B'), true);
  f.api.disconnected('B'); assert.equal(f.api.isBusy('B'), false); f.api.dispose();
});
test('stage join request expires after 45 seconds and may be requested again', () => {
  const f = fixture();
  const started = f.start();
  const callId = started.call.id;

  f.send('B', 'group_call_join_request', {
    groupId: 'g',
    callId,
  });

  assert.equal(
    f.sent.findLast(
      x => x.to === 'B' && x.type === 'group_call_join_request_status',
    ).data.pending,
    true,
  );

  f.advance(45000);

  f.send('A', 'group_call_join_response', {
    groupId: 'g',
    callId,
    target: 'B',
    accepted: true,
  });

  const lateResponse = f.sent.findLast(
    x => x.to === 'B' && x.type === 'group_call_join_response',
  );

  assert.equal(lateResponse, undefined);

  f.send('B', 'group_call_join', {
    groupId: 'g',
    callId,
    requestId: 'expired-B',
  });

  assert.equal(f.sent.at(-1).type, 'group_call_error');

  f.send('B', 'group_call_join_request', {
    groupId: 'g',
    callId,
  });

  f.send('A', 'group_call_join_response', {
    groupId: 'g',
    callId,
    target: 'B',
    accepted: true,
  });

  f.send('B', 'group_call_join', {
    groupId: 'g',
    callId,
    requestId: 'fresh-B',
  });

  assert.equal(f.joined('B').requestId, 'fresh-B');
  assert.equal(f.api.isBusy('B'), true);

  f.api.dispose();
});
test('duplicate request is idempotent and does not reinvite', () => {
  const f = fixture(); const a = f.start(); const count = f.sent.length; const again = f.start();
  assert.equal(again.sessionId, a.sessionId); assert.equal(f.sent.length, count + 1); f.api.dispose();
});
test('replacement login does not remain busy on its obsolete socket', () => {
  const f = fixture(); f.start(); f.join('B'); const old = f.packet('B');
  f.onlineUsers.set('B', { u: 'B' });
  f.send('B', 'group_call_join_request', { groupId: 'g', callId: old.callId });
  f.send('A', 'group_call_join_response', { groupId: 'g', callId: old.callId, target: 'B', accepted: true });
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
