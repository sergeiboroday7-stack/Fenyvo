'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { TemporaryJoinApproval } = require('../server_temporary_join_approval');

// Exercise the ACTUAL branches extracted from the provided server.js, with
// in-memory sockets and persistence. No production network or user data.
const server = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8').replace(/\r\n/g, '\n');
function between(from, to) {
  const i = server.indexOf(from), j = server.indexOf(to, i + from.length);
  assert.ok(i >= 0 && j > i, `Cannot isolate server handler: ${from}`);
  return server.slice(i, j);
}
const getSessionSource = between('function getTemporaryContactSessionForUser(', 'function getAcceptedCommunicationContacts(');
const decisionJoinHandlers = between("          if (type === 'temporary_contact_capabilities_get')", "          if (type === 'temporary_message')");
const messageAndBundles = between("          if (type === 'temporary_message')", "          // ====================================\n          // COMMUNICATION REQUESTS");
const runner = new Function('ctx', `
  const { ws, currentUser, type, data, temporaryContacts,
    temporaryContactSessions, temporaryJoinApprovals, temporaryE2eeBundles,
    onlineUsers, send, saveJsonObjectFile, TEMPORARY_CONTACTS_FILE,
    crypto } = ctx;
  const WebSocket = {OPEN: 1};
  function isBase64Value(value, maxLength = 8192) {
    return typeof value === 'string' && value.length > 0 &&
      value.length <= maxLength && /^[A-Za-z0-9+/]+={0,2}$/.test(value);
  }
  function positiveKeyId(value) {const n = Number(value); return Number.isSafeInteger(n) && n > 0 ? n : null;}
  function validPublicPreKey(value, kyber = false) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    const id = positiveKeyId(value.id);
    if (!id || !isBase64Value(value.publicKey, kyber ? 8192 : 256)) return null;
    if (kyber && !isBase64Value(value.signature, 256)) return null;
    return kyber ? {id, publicKey: value.publicKey, signature: value.signature} : {id, publicKey: value.publicKey};
  }
  ${getSessionSource}
  ${decisionJoinHandlers}
  ${messageAndBundles}
  throw new Error('Unrecognized temporary event: ' + type);
`);

function fixture() {
  const token = 'a'.repeat(64);
  const owner = {name: 'owner', readyState: 1};
  const guest = {name: 'guest', readyState: 1};
  const intruder = {name: 'intruder', readyState: 1};
  const temporaryContacts = {[token]: {owner:'owner',approvalVersion:1,createdAt:new Date().toISOString(),expiresAt:new Date(Date.now()+3600000).toISOString(),allowMessages:true}};
  const temporaryContactSessions = new Map();
  const temporaryJoinApprovals = new TemporaryJoinApproval();
  const temporaryE2eeBundles = new Map();
  const onlineUsers = new Map([['owner',owner],['guest',guest],['intruder',intruder]]);
  const messages = [];
  let persistenceFails = false;
  const send=(ws,type,data)=>messages.push({target:ws.name,type,data});
  const saveJsonObjectFile=()=>{if (persistenceFails) throw new Error('I/O failure');};
  const event=(ws, currentUser, type, data={})=> {
    messages.length=0;
    runner({ws,currentUser,type,data,temporaryContacts,temporaryContactSessions,
      temporaryJoinApprovals,temporaryE2eeBundles,onlineUsers,send,
      saveJsonObjectFile,TEMPORARY_CONTACTS_FILE:'test-only-in-memory',crypto});
    return messages.slice();
  };
  return {token,owner,guest,intruder,temporaryContacts,temporaryContactSessions,
    temporaryE2eeBundles,onlineUsers,event,setPersistenceFails:(v)=>persistenceFails=v};
}
function find(sent,type,target) {return sent.find(x=>x.type===type && (!target||x.target===target))?.data;}
function approve(f) {
  const sent=f.event(f.guest,'guest','temporary_contact_join',{token:f.token,approvalVersion:1});
  assert.equal(find(sent,'temporary_contact_join_pending','guest')?.success,true);
  assert.equal(f.temporaryContactSessions.size,0);
  const id=find(sent,'temporary_contact_join_request','owner').requestId;
  const allowed=f.event(f.owner,'owner','temporary_contact_join_decision',{requestId:id,approved:true});
  const joined=find(allowed,'temporary_contact_joined','guest');
  assert.equal(joined?.success,true);
  assert.equal(find(allowed,'temporary_contact_joined','owner')?.success,true);
  return {id, sessionId:joined.sessionId};
}

test('real server event branches: pending, socket-bound consent, replay and single guest',()=>{
  const f=fixture();
  let sent=f.event(f.guest,'guest','temporary_contact_join',{token:f.token,approvalVersion:1});
  const request=find(sent,'temporary_contact_join_request','owner');
  assert.match(request.requestId,/^[0-9a-f]{32}$/);
  assert.equal(f.temporaryContacts[f.token].guest,undefined);
  assert.equal(f.temporaryContactSessions.size,0);
  sent=f.event(f.intruder,'intruder','temporary_contact_join',{token:f.token,approvalVersion:1});
  assert.equal(find(sent,'temporary_contact_joined','intruder')?.success,false);
  sent=f.event(f.guest,'guest','temporary_contact_pending_get');
  assert.deepEqual(find(sent,'temporary_contact_pending_list','guest')?.requests,[]);
  sent=f.event(f.owner,'owner','temporary_contact_pending_get');
  assert.equal(find(sent,'temporary_contact_pending_list','owner').requests[0].requestId,request.requestId);
  sent=f.event(f.intruder,'intruder','temporary_contact_join_decision',{requestId:request.requestId,approved:true});
  assert.equal(find(sent,'temporary_contact_join_decision_result','intruder')?.success,false);
  sent=f.event({name:'fake-owner',readyState:1},'owner','temporary_contact_join_decision',{requestId:request.requestId,approved:true});
  assert.equal(find(sent,'temporary_contact_join_decision_result','fake-owner')?.success,false);
  sent=f.event(f.owner,'owner','temporary_contact_join_decision',{requestId:request.requestId,approved:true});
  assert.equal(find(sent,'temporary_contact_joined','guest')?.success,true);
  assert.equal(find(sent,'temporary_contact_joined','owner').requestId,request.requestId);
  assert.equal(f.temporaryContacts[f.token].guest,'guest');
  assert.equal(f.temporaryContactSessions.size,1);
  sent=f.event(f.owner,'owner','temporary_contact_join_decision',{requestId:request.requestId,approved:true});
  assert.equal(find(sent,'temporary_contact_join_decision_result','owner')?.success,false);
  sent=f.event(f.intruder,'intruder','temporary_contact_join',{token:f.token,approvalVersion:1});
  assert.equal(find(sent,'temporary_contact_joined','intruder')?.success,false);
});

test('real server event branches: E2EE relay is inaccessible before approval, to outsiders and after revoke',()=>{
  const f=fixture();
  const msg = {sessionId:'f'.repeat(48),messageId:'msg-id-123',cipherType:3,ciphertext:'YWJjZA=='};
  let sent=f.event(f.guest,'guest','temporary_message',msg);
  assert.equal(find(sent,'temporary_message_status','guest')?.success,false);
  const {sessionId}=approve(f);
  msg.sessionId=sessionId;
  sent=f.event(f.intruder,'intruder','temporary_message',msg);
  assert.equal(find(sent,'temporary_message_status','intruder')?.success,false);
  sent=f.event(f.owner,'owner','temporary_message',msg);
  assert.equal(find(sent,'temporary_message','guest')?.e2ee,true);
  assert.equal(find(sent,'temporary_message_status','owner')?.success,true);
  f.temporaryContacts[f.token].revoked=true;
  sent=f.event(f.owner,'owner','temporary_message',msg);
  assert.equal(find(sent,'temporary_message_status','owner')?.success,false);
  sent=f.event(f.guest,'guest','temporary_e2ee_bundle_get',{sessionId});
  assert.equal(find(sent,'temporary_e2ee_prekey_bundle','guest')?.available,false);
  assert.equal(f.temporaryContactSessions.size,0);
});

test('real server event branches: persistence failure cannot create approved session',()=>{
  const f=fixture();
  const sent=f.event(f.guest,'guest','temporary_contact_join',{token:f.token,approvalVersion:1});
  const requestId=find(sent,'temporary_contact_join_request','owner').requestId;
  f.setPersistenceFails(true);
  const result=f.event(f.owner,'owner','temporary_contact_join_decision',{requestId,approved:true});
  assert.equal(find(result,'temporary_contact_joined','guest')?.success,false);
  assert.equal(f.temporaryContactSessions.size,0);
  assert.equal(f.temporaryContacts[f.token].guest,undefined);
});

test('real server event branches: returning accepted guest reuses the same session',()=>{
  const f=fixture();
  const {sessionId}=approve(f);
  const result=f.event(f.guest,'guest','temporary_contact_join',{token:f.token,approvalVersion:1});
  assert.equal(find(result,'temporary_contact_joined','guest').sessionId,sessionId);
});

test('real Flutter event names match server consent protocol',()=>{
  const service=fs.readFileSync(path.join(__dirname,'..','lib/services/socket_service.dart'),'utf8');
  const screen=fs.readFileSync(path.join(__dirname,'..','lib/screens/temporary_contact_screen.dart'),'utf8');
  for (const name of ['temporary_contact_pending_get','temporary_contact_join_decision','temporary_contact_join']) {
    assert.ok(service.includes(name),`Missing outgoing event ${name}`);
    assert.ok(server.includes(`type === '${name}'`),`Missing server event ${name}`);
  }
  for (const name of ['temporary_contact_pending_list','temporary_contact_join_request','temporary_contact_join_pending','temporary_contact_join_decision_result','temporary_contact_joined']) {
    assert.ok(server.includes(`'${name}'`),`Missing server response ${name}`);
    assert.ok(screen.includes(`type == '${name}'`),`Missing screen handler ${name}`);
  }
});

test('real server event branches: a cached session follows live message permissions and expiry', () => {
  const f=fixture();
  const {sessionId}=approve(f);
  const msg={sessionId,messageId:'cached-permissions-1',cipherType:3,ciphertext:'YWJjZA=='};
  f.temporaryContacts[f.token].allowMessages=false;
  let sent=f.event(f.owner,'owner','temporary_message',msg);
  assert.equal(find(sent,'temporary_message_status','owner')?.success,false);
  assert.equal(f.temporaryContactSessions.get(sessionId)?.allowMessages,false);
  f.temporaryContacts[f.token].allowMessages=true;
  f.temporaryContacts[f.token].expiresAt=new Date(Date.now()-1).toISOString();
  sent=f.event(f.owner,'owner','temporary_message',msg);
  assert.equal(find(sent,'temporary_message_status','owner')?.success,false);
  assert.equal(f.temporaryContactSessions.has(sessionId),false);
});

test('real server event branches: changing persisted guest revokes cached session access', () => {
  const f=fixture();
  const {sessionId}=approve(f);
  f.temporaryContacts[f.token].guest='intruder';
  const msg={sessionId,messageId:'changed-guest-1',cipherType:3,ciphertext:'YWJjZA=='};
  const sent=f.event(f.guest,'guest','temporary_message',msg);
  assert.equal(find(sent,'temporary_message_status','guest')?.success,false);
  assert.equal(f.temporaryContactSessions.has(sessionId),false);
});
