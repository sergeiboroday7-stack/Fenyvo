'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { TemporaryJoinApproval } = require('../server_temporary_join_approval');

const token = 'a'.repeat(64);
const ownerSocket = {};
const guestSocket = {};
const payload = { token, owner: 'OWNER', guest: 'GUEST', ownerSocket, guestSocket };

test('new guest requires approval before a join is granted', () => {
  const approval = new TemporaryJoinApproval();
  const request = approval.request(payload);
  assert.equal(request.ok, true);
  assert.match(request.requestId, /^[0-9a-f]{32}$/);
  assert.equal(approval.byId.size, 1);
  assert.equal(approval.takeDecision({requestId: request.requestId, owner: 'OWNER', ownerSocket}).ok, true);
  assert.equal(approval.byId.size, 0);
});

test('other account cannot approve', () => {
  const a = new TemporaryJoinApproval();
  const r = a.request(payload);
  assert.equal(a.takeDecision({ requestId: r.requestId, owner: 'attacker', ownerSocket }).ok, false);
  assert.equal(a.byId.size, 1);
});

test('different socket cannot approve as owner', () => {
  const a = new TemporaryJoinApproval();
  const r = a.request(payload);
  assert.equal(a.takeDecision({ requestId: r.requestId, owner: 'owner', ownerSocket: {} }).ok, false);
  assert.equal(a.byId.size, 1);
});

test('same guest and sockets get idempotent request, other guest blocked', () => {
  const a = new TemporaryJoinApproval();
  const r = a.request(payload);
  assert.deepEqual(a.request(payload), {...r, repeated: true});
  assert.equal(a.request({ ...payload, guest: 'OTHER' }).ok, false);
  assert.equal(a.byId.size, 1);
});

test('expired request cannot be approved', () => {
  let now = 500;
  const a = new TemporaryJoinApproval({ ttlMs: 100, now: () => now });
  const r = a.request(payload);
  now = 601;
  assert.equal(a.takeDecision({ requestId: r.requestId, owner: 'owner', ownerSocket }).ok, false);
  assert.equal(a.byId.size, 0);
});

test('decision cannot be replayed', () => {
  const a = new TemporaryJoinApproval();
  const r = a.request(payload);
  assert.equal(a.takeDecision({ requestId: r.requestId, owner: 'owner', ownerSocket }).ok, true);
  assert.equal(a.takeDecision({ requestId: r.requestId, owner: 'owner', ownerSocket }).ok, false);
});

test('fails closed on malformed token or owner equals guest', () => {
  const a = new TemporaryJoinApproval();
  assert.equal(a.request({...payload, token: 'oops'}).ok, false);
  assert.equal(a.request({...payload, guest: 'owner'}).ok, false);
  assert.equal(a.byId.size, 0);
});

test('pending queue is bounded', () => {
  const a = new TemporaryJoinApproval({ maxPending: 1 });
  assert.equal(a.request(payload).ok, true);
  assert.equal(a.request({...payload, token: 'b'.repeat(64) }).ok, false);
});


test('owner can recover a pending request on the same authenticated socket', () => {
  const a = new TemporaryJoinApproval();
  const r = a.request(payload);
  assert.deepEqual(a.pendingForOwner({ owner: 'OWNER', ownerSocket }), [{
    token, requestId: r.requestId, expiresAt: new Date(r.expiresAt).toISOString(),
  }]);
  assert.deepEqual(a.pendingForOwner({ owner: 'GUEST', ownerSocket }), []);
  assert.deepEqual(a.pendingForOwner({ owner: 'OWNER', ownerSocket: {} }), []);
  assert.equal(a.takeDecision({ requestId: r.requestId, owner: 'OWNER', ownerSocket }).ok, true);
  assert.deepEqual(a.pendingForOwner({ owner: 'OWNER', ownerSocket }), []);
});

test('expired pending approvals are not recovered', () => {
  let now = 1000;
  const a = new TemporaryJoinApproval({ ttlMs: 100, now: () => now });
  a.request(payload);
  now = 1101;
  assert.deepEqual(a.pendingForOwner({ owner: 'OWNER', ownerSocket }), []);
});
