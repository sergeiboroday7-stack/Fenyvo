'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { TemporaryJoinApproval } = require('../server_temporary_join_approval');

// Exercise the actual, changed server branches against synthetic sockets.
// No real user records, socket connections, or live server.
const root = path.join(__dirname, '..');
const server = fs.readFileSync(path.join(root, 'server.js'), 'utf8').replace(/\r\n/g, '\n');
const from = "          if (type === 'temporary_contact_capabilities_get')";
const to = "          if (type === 'temporary_message')";
const a = server.indexOf(from), b = server.indexOf(to, a + from.length);
assert.ok(a !== -1 && b > a, 'Missing server protocol handlers');
const run = new Function('c', `
const {type,data,currentUser,ws,onlineUsers,temporaryContacts,
  temporaryContactSessions,temporaryJoinApprovals,send,saveJsonObjectFile,
  TEMPORARY_CONTACTS_FILE,crypto}=c;
const WebSocket={OPEN:1};
${server.slice(a,b)}
throw new Error('Unknown event '+type);`);

function fixture(){
  const owner={name:'owner',readyState:1};
  const guest={name:'guest',readyState:1};
  const third={name:'third',readyState:1};
  const temporaryContacts=Object.create(null);
  const temporaryContactSessions=new Map();
  const temporaryJoinApprovals=new TemporaryJoinApproval();
  const onlineUsers=new Map([['owner',owner],['guest',guest],['third',third]]);
  const responses=[];
  const send=(s,type,data)=>responses.push({who:s.name,type,data});
  const saveJsonObjectFile=()=>{};
  function event(ws, currentUser, type, data={}) {
    responses.length=0;
    run({type,data,currentUser,ws,onlineUsers,temporaryContacts,
      temporaryContactSessions,temporaryJoinApprovals,send,
      saveJsonObjectFile,TEMPORARY_CONTACTS_FILE:'synthetic',crypto});
    return [...responses];
  }
  return {owner,guest,third,temporaryContacts,temporaryContactSessions,event};
}
function get(result,type,who){return result.find(x=>x.type===type&&(!who||x.who===who))?.data;}
function validLegacyInvite(f,token){
 f.temporaryContacts[token]={owner:'owner',createdAt:new Date(Date.now()-60000).toISOString(),expiresAt:new Date(Date.now()+3600000).toISOString(),allowMessages:true,revoked:false};
}

test('capability nonce only responds to authenticated owner and exact format',()=>{
 const f=fixture(), nonce='a'.repeat(32);
 assert.equal(get(f.event(f.owner,'owner','temporary_contact_capabilities_get',{requestId:nonce}), 'temporary_contact_capabilities').approvalVersion,1);
 assert.equal(get(f.event(f.owner,null,'temporary_contact_capabilities_get',{requestId:nonce}),'temporary_contact_capabilities'),undefined);
 assert.equal(get(f.event(f.owner,'owner','temporary_contact_capabilities_get',{requestId:'bad'}),'temporary_contact_capabilities'),undefined);
});

test('unversioned clients 12317/12318 cannot create a link that bypasses consent',()=>{
 const f=fixture();
 const res=f.event(f.owner,'owner','temporary_contact_create',{requestId:'old',durationMinutes:60});
 assert.equal(get(res,'temporary_contact_created').success,false);
 assert.equal(get(res,'temporary_contact_created').code,'client_upgrade_required');
 assert.equal(Object.keys(f.temporaryContacts).length,0);
});

test('new invitations are tagged approval v1 and cannot be joined by old guest',()=>{
 const f=fixture();
 const made=get(f.event(f.owner,'owner','temporary_contact_create',{requestId:'new',approvalVersion:1,durationMinutes:60}),'temporary_contact_created');
 assert.equal(made.success,true);
 assert.equal(made.ownerApprovalRequired,true);
 assert.equal(made.approvalVersion,1);
 assert.equal(f.temporaryContacts[made.token].approvalVersion,1);
 const old=get(f.event(f.guest,'guest','temporary_contact_join',{token:made.token}),'temporary_contact_joined','guest');
 assert.equal(old.success,false);
 assert.equal(old.code,'client_upgrade_required');
 assert.equal(f.temporaryContactSessions.size,0);
 const requested=f.event(f.guest,'guest','temporary_contact_join',{token:made.token,approvalVersion:1});
 assert.equal(get(requested,'temporary_contact_join_pending','guest').success,true);
 const id=get(requested,'temporary_contact_join_request','owner').requestId;
 const joined=f.event(f.owner,'owner','temporary_contact_join_decision',{requestId:id,approved:true});
 assert.equal(get(joined,'temporary_contact_joined','guest').success,true);
 assert.equal(f.temporaryContactSessions.size,1);
});

test('legacy untagged pre-update invitation can be joined only by legacy guest',()=>{
 const f=fixture(), token='b'.repeat(64);
 validLegacyInvite(f,token);
 const modern=get(f.event(f.guest,'guest','temporary_contact_join',{token,approvalVersion:1}),'temporary_contact_joined');
 assert.equal(modern.success,false);
 assert.equal(modern.code,'legacy_invite_unsupported');
 assert.equal(f.temporaryContacts[token].guest,undefined);
 const old=f.event(f.guest,'guest','temporary_contact_join',{token});
 const joined=get(old,'temporary_contact_joined','guest');
 assert.equal(joined.success,true);
 assert.equal(f.temporaryContacts[token].guest,'guest');
 assert.equal(get(old,'temporary_contact_joined','owner').sessionId,joined.sessionId);
});

test('existing legacy guest reconnects after upgrade, without recreating session',()=>{
 const f=fixture(), token='c'.repeat(64);
 validLegacyInvite(f,token);
 const first=get(f.event(f.guest,'guest','temporary_contact_join',{token}),'temporary_contact_joined','guest');
 const next=get(f.event(f.guest,'guest','temporary_contact_join',{token,approvalVersion:1}),'temporary_contact_joined','guest');
 assert.equal(next.success,true);
 assert.equal(next.sessionId,first.sessionId);
 assert.equal(f.temporaryContactSessions.size,1);
});

test('malformed untagged invites do not get legacy exception',()=>{
 const f=fixture(), token='d'.repeat(64);
 f.temporaryContacts[token]={owner:'owner',expiresAt:new Date(Date.now()+3600000).toISOString(),revoked:false};
 const r=get(f.event(f.guest,'guest','temporary_contact_join',{token}),'temporary_contact_joined');
 assert.equal(r.success,false);
 assert.equal(f.temporaryContactSessions.size,0);
});

test('new client never creates/joins without capability proof in Flutter code',()=>{
 const service=fs.readFileSync(path.join(root,'lib/services/socket_service.dart'),'utf8');
 const screen=fs.readFileSync(path.join(root,'lib/screens/temporary_contact_screen.dart'),'utf8');
 assert.match(service,/supportsTemporaryOwnerApproval\(\)/);
 assert.match(service,/_temporaryApprovalVerifiedScope/);
 assert.match(service,/temporary_contact_capabilities_get/);
 assert.match(service,/ownerApprovalRequired/);
 assert.match(service,/joinTemporaryContactSecurely/);
 assert.match(service,/'approvalVersion': 1/);
 assert.match(screen,/await SocketService\.instance\.joinTemporaryContactSecurely\(value\)/);
});
