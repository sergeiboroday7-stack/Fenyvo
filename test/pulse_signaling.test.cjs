'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createPulseSignaling } = require('../pulse_signaling');

function fixture() {
  const sent = [];
  const pushes = [];
  const timers = [];
  const busy = new Set();
  let time = 1000;
  const onlineUsers = new Map(
    ['Alice', 'Bob', 'Eve'].map(user => [user, { user }]),
  );
  const api = createPulseSignaling({
    send: (ws, type, data) => sent.push({ to: ws.user, type, data }),
    onlineUsers,
    registeredUsers: { Alice: {}, Bob: {}, Eve: {} },
    isBusy: user => busy.has(user),
    push: async (to, pulse) => {
      pushes.push({ to, pulse });
      return true;
    },
    now: () => time,
    later: (fn, ms) => {
      const timer = { fn, ms, cancelled: false };
      timers.push(timer);
      return timer;
    },
    cancel: timer => {
      if (timer) timer.cancelled = true;
    },
  });
  const send = (user, type, data = {}) =>
    api.handle(onlineUsers.get(user), user, type, data);
  const request = (from = 'Alice', to = 'Bob', video = true) => {
    send(from, 'pulse_request', {
      to,
      video,
      windowMinutes: 60,
      requestId: `request-${from}`,
    });
    return sent.findLast(
      event => event.to === from && event.type === 'pulse_state',
    ).data.pulse;
  };
  return {
    api,
    sent,
    pushes,
    timers,
    busy,
    onlineUsers,
    send,
    request,
    advance: milliseconds => {
      time += milliseconds;
    },
  };
}

test('request notifies both sides without exposing call credentials', async () => {
  const f = fixture();
  const pulse = f.request();
  await Promise.resolve();

  assert.equal(f.sent[0].to, 'Alice');
  assert.equal(f.sent[0].type, 'pulse_state');
  assert.equal(f.sent[1].to, 'Bob');
  assert.equal(f.sent[1].type, 'pulse_invite');
  assert.equal(pulse.from, 'Alice');
  assert.equal(pulse.to, 'Bob');
  assert.equal(pulse.video, true);
  assert.equal(pulse.expiresAt, 1000 + 60 * 60000);
  assert.equal(pulse.sdp, undefined);
  assert.equal(pulse.callToken, undefined);
  assert.equal(f.pushes.length, 1);
  assert.equal(f.pushes[0].to, 'Bob');
  f.api.dispose();
});

test('recipient acceptance creates one synchronized countdown', () => {
  const f = fixture();
  const pulse = f.request();
  f.sent.length = 0;

  f.send('Bob', 'pulse_accept', {
    pulseId: pulse.id,
    requestId: 'accept-Bob',
  });

  const matches = f.sent.filter(event => event.type === 'pulse_match');
  assert.deepEqual(matches.map(event => event.to), ['Alice', 'Bob']);
  assert.ok(matches.every(event => event.data.pulse.state === 'matched'));
  assert.ok(matches.every(event => event.data.startsAt === 5000));
  assert.equal(f.api.isReserved('Alice'), true);
  assert.equal(f.api.isReserved('Bob'), true);
  f.api.dispose();
});

test('reciprocal requests match immediately and choose the safer audio mode', () => {
  const f = fixture();
  f.request('Alice', 'Bob', true);
  f.sent.length = 0;

  f.request('Bob', 'Alice', false);

  const matches = f.sent.filter(event => event.type === 'pulse_match');
  assert.equal(matches.length, 2);
  assert.ok(matches.every(event => event.data.pulse.video === false));
  f.api.dispose();
});

test('authentication, recipient and busy checks reject unsafe requests', () => {
  const f = fixture();
  assert.equal(f.api.handle({ user: 'fake' }, 'Alice', 'pulse_sync', {}), true);
  assert.equal(f.sent.at(-1).type, 'pulse_error');

  for (const to of ['', 'Alice', 'Unknown', '__proto__']) {
    f.send('Alice', 'pulse_request', { to, requestId: `bad-${to}` });
    assert.equal(f.sent.at(-1).type, 'pulse_error');
  }

  f.busy.add('Bob');
  f.send('Alice', 'pulse_request', { to: 'Bob', requestId: 'busy' });
  assert.equal(f.sent.at(-1).type, 'pulse_error');
  assert.match(f.sent.at(-1).data.reason, /разговаривает/);
  f.api.dispose();
});

test('outsiders cannot accept or cancel another pair pulse', () => {
  const f = fixture();
  const pulse = f.request();

  f.send('Eve', 'pulse_accept', { pulseId: pulse.id, requestId: 'evil' });
  assert.equal(f.sent.at(-1).to, 'Eve');
  assert.equal(f.sent.at(-1).type, 'pulse_error');

  f.send('Alice', 'pulse_decline', {
    pulseId: pulse.id,
    requestId: 'wrong-side',
  });
  assert.equal(f.sent.at(-1).type, 'pulse_error');
  assert.equal(f.api.isReserved('Alice'), false);
  f.api.dispose();
});

test('decline, cancellation and expiry close the pulse for both users', () => {
  for (const action of ['pulse_decline', 'pulse_cancel', 'expiry']) {
    const f = fixture();
    const pulse = f.request();
    f.sent.length = 0;

    if (action === 'pulse_decline') {
      f.send('Bob', action, { pulseId: pulse.id });
    } else if (action === 'pulse_cancel') {
      f.send('Alice', action, { pulseId: pulse.id });
    } else {
      f.timers[0].fn();
    }

    const closed = f.sent.filter(event => event.type === 'pulse_closed');
    assert.deepEqual(closed.map(event => event.to), ['Alice', 'Bob']);
    assert.ok(
      closed.every(event =>
        ['declined', 'cancelled', 'expired'].includes(event.data.reason),
      ),
    );
    f.api.dispose();
  }
});

test('offline recipient restores the invitation through authenticated sync', () => {
  const f = fixture();
  f.onlineUsers.delete('Bob');
  const pulse = f.request();
  assert.equal(f.sent.some(event => event.to === 'Bob'), false);

  f.onlineUsers.set('Bob', { user: 'Bob' });
  f.send('Bob', 'pulse_sync');
  const sync = f.sent.findLast(
    event => event.to === 'Bob' && event.type === 'pulse_sync',
  );
  assert.equal(sync.data.pulses.length, 1);
  assert.equal(sync.data.pulses[0].id, pulse.id);
  f.api.dispose();
});

test('ordinary messenger traffic is not intercepted', () => {
  const f = fixture();
  assert.equal(f.send('Alice', 'message', { text: 'hello' }), false);
  assert.equal(f.sent.length, 0);
  f.api.dispose();
});
