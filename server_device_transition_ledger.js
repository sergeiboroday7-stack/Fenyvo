'use strict';
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto'),{isDeepStrictEqual}=require('node:util');
const {saveRecoveryJsonAtomic}=require('./server_recovery_storage');
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,hex=/^[0-9a-f]{64}$/;
const clone=x=>JSON.parse(JSON.stringify(x)),hash=x=>createHash('sha256').update(x).digest('hex');
const plain=x=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&[Object.prototype,null].includes(Object.getPrototypeOf(x));
function exact(x,keys){if(!plain(x)||Object.keys(x).length!==keys.length||keys.some(k=>!Object.hasOwn(x,k)))throw Error('Invalid ledger fields');}
function publicKey(value){if(typeof value!=='string')throw Error('Invalid public key');const b=Buffer.from(value,'base64');if(b.length!==33||b[0]!==5||b.toString('base64')!==value)throw Error('Invalid public key');return b;}
function certificate(value){
 exact(value,['payload','signature']);const p=value.payload;
 exact(p,['purpose','accountId','username','oldIdentityHash','newIdentityKey','fromEpoch','toEpoch','issuedAt','transferNonce']);
 if(p.purpose!=='fenyvo-device-key-transition-v1'||typeof p.accountId!=='string'||!uuid.test(p.accountId)||
 typeof p.username!=='string'||!p.username||p.username!==p.username.trim()||Buffer.byteLength(p.username)>128||/[\x00-\x1f\x7f]/.test(p.username)||
 typeof p.oldIdentityHash!=='string'||!hex.test(p.oldIdentityHash)||typeof p.transferNonce!=='string'||!hex.test(p.transferNonce)||
 !Number.isSafeInteger(p.fromEpoch)||p.fromEpoch<0||!Number.isSafeInteger(p.toEpoch)||p.toEpoch!==p.fromEpoch+1||
 !Number.isSafeInteger(p.issuedAt)||p.issuedAt<0||hash(publicKey(p.newIdentityKey))===p.oldIdentityHash)throw Error('Invalid certificate binding');
 if(typeof value.signature!=='string')throw Error('Invalid certificate signature encoding');
 const sig=Buffer.from(value.signature,'base64');if(sig.length!==64||sig.toString('base64')!==value.signature)throw Error('Invalid certificate signature encoding');
 // Opaque Signal signature: recipients MUST cryptographically verify it against pinned trust.
 return clone(value);
}
function validateState(state){
 exact(state,['version','accounts']);if(state.version!==1||!plain(state.accounts)||Object.keys(state.accounts).length>100000)throw Error('Invalid ledger state');
 for(const [id,row]of Object.entries(state.accounts)){
  if(!uuid.test(id))throw Error('Invalid ledger account');exact(row,['username','initialIdentityKey','identityKey','epoch','certificates']);
  let key=publicKey(row.initialIdentityKey),epoch=0;
  if(!Array.isArray(row.certificates)||row.certificates.length<1||row.certificates.length>1024)throw Error('Invalid certificate history');
  const nonces=new Set();
  for(const raw of row.certificates){const p=certificate(raw).payload;
   if(p.accountId!==id||p.username!==row.username||p.fromEpoch!==epoch||p.oldIdentityHash!==hash(key)||nonces.has(p.transferNonce))throw Error('Broken certificate history');
   nonces.add(p.transferNonce);key=publicKey(p.newIdentityKey);epoch=p.toEpoch;
  }
  if(row.epoch!==epoch||row.identityKey!==key.toString('base64'))throw Error('Invalid ledger head');
 }
 return state;
}
function createDeviceTransitionLedger(o){
 if(!o||typeof o.file!=='string'||!path.isAbsolute(o.file)||o.singleWriter!==true)throw Error('Absolute file and explicit single-writer deployment required');
 for(const k of ['getOwner','getPendingOwner','getActiveSocket','getAccountId','getCandidateKey','getCurrentIdentity','getCredentialStamp','getPendingChallenge','consumeChallenge'])if(typeof o[k]!=='function')throw Error('Required provider: '+k);
 const now=o.now||Date.now,write=o.writeAtomic||saveRecoveryJsonAtomic,max=o.maxPending??64;
 if(typeof now!=='function'||typeof write!=='function'||!Number.isInteger(max)||max<1||max>1000)throw Error('Invalid ledger options');
 function read(){if(!fs.existsSync(o.file))return{version:1,accounts:{}};if(fs.statSync(o.file).size>33554432)throw Error('Ledger too large');return validateState(JSON.parse(fs.readFileSync(o.file,'utf8')));}
 let state=read();const staged=new Map(),owners=new Map();
 function time(){const t=now();if(!Number.isSafeInteger(t)||t<0)throw Error('Invalid clock');return t;}
 function fresh(){if(!isDeepStrictEqual(read(),state))throw Error('Ledger changed; reload required');}
 function drop(socket){const r=staged.get(socket);if(!r)return;staged.delete(socket);if(owners.get(r.username)===socket)owners.delete(r.username);socket.removeListener('close',r.close);}
 function bound(r){return r.old.readyState===1&&r.next.readyState===1&&o.getOwner(r.old)===r.username&&o.getActiveSocket(r.username)===r.old&&
  !o.getOwner(r.next)&&o.getPendingOwner(r.next)===r.username&&o.getAccountId(r.username)===r.accountId&&
  o.getCandidateKey(r.next)===r.candidate&&o.getCurrentIdentity(r.username)===r.oldKey&&o.getCredentialStamp(r.username)===r.stamp;}
 function prune(t){for(const[s,r]of staged)if(t>=r.expiresAt||!bound(r))drop(s);}
 function stage(old,next,rawCertificate){
  const t=time();prune(t);fresh();const cert=certificate(rawCertificate),p=cert.payload,username=o.getOwner(old),accountId=o.getAccountId(username),candidate=o.getCandidateKey(next),oldKey=o.getCurrentIdentity(username),stamp=o.getCredentialStamp(username);
  if(!old||!next||old===next||typeof stamp!=='string'||!stamp||username!==p.username||accountId!==p.accountId||candidate!==p.newIdentityKey||hash(publicKey(oldKey))!==p.oldIdentityHash)throw Error('Invalid authenticated transition binding');
  const row=state.accounts[accountId];if(row&&(row.username!==username||row.identityKey!==oldKey||row.certificates.length>=1024))throw Error('Current identity differs from ledger');
  if(p.fromEpoch!==(row?.epoch??0)||row?.certificates.some(x=>x.payload.transferNonce===p.transferNonce))throw Error('Stale transition epoch or nonce');
  const challenge=o.getPendingChallenge(next);
  exact(challenge,['purpose','accountId','candidateHash','nonce','issuedAt','expiresAt']);
  if(challenge.purpose!=='fenyvo-device-transfer-v1'||challenge.accountId!==accountId||challenge.candidateHash!==hash(publicKey(candidate))||
   challenge.nonce!==p.transferNonce||challenge.issuedAt!==p.issuedAt||!Number.isSafeInteger(challenge.expiresAt)||
   challenge.issuedAt>t||challenge.expiresAt<=t||challenge.expiresAt-challenge.issuedAt>300000)throw Error('Invalid live challenge');
  const r={old,next,username,accountId,candidate,oldKey,stamp,cert,expiresAt:challenge.expiresAt,close:()=>drop(next)};
  if(!bound(r))throw Error('Transition actors changed');
  const previous=owners.get(username);if(!previous&&!staged.has(next)&&staged.size>=max)throw Error('Transition capacity reached');
  // Real challenge provider must enforce one-use and the exact old/new socket binding.
  const consumed=o.consumeChallenge(old,next,p.transferNonce);if(!isDeepStrictEqual(consumed,challenge))throw Error('Challenge consumption mismatch');
  if(previous)drop(previous);drop(next);staged.set(next,r);owners.set(username,next);next.once('close',r.close);
  return Object.freeze({transferNonce:p.transferNonce,fromEpoch:p.fromEpoch,toEpoch:p.toEpoch});
 }
 function commit(next,nonce){
  const t=time();prune(t);const r=staged.get(next);if(!r||r.cert.payload.transferNonce!==nonce||!bound(r))throw Error('Transition unavailable');
  fresh();const prior=state.accounts[r.accountId];
  if((prior?.epoch??0)!==r.cert.payload.fromEpoch||(prior&&prior.identityKey!==r.oldKey))throw Error('Transition head changed');
  const row={username:r.username,initialIdentityKey:prior?.initialIdentityKey??r.oldKey,identityKey:r.candidate,
   epoch:r.cert.payload.toEpoch,certificates:[...(prior?.certificates??[]),r.cert]};
  const updated=validateState({version:1,accounts:{...state.accounts,[r.accountId]:row}});
  if(Buffer.byteLength(JSON.stringify(updated,null,2))>33554432)throw Error('Ledger capacity reached');
  if(write(o.file,updated)!==true)throw Error('Transition not persisted');
  if(!isDeepStrictEqual(read(),updated))throw Error('Transition persistence readback mismatch');
  state=updated;drop(next);return Object.freeze({accountId:r.accountId,epoch:row.epoch,transferNonce:nonce,committed:true});
 }
 function status(next,nonce){
  if(typeof nonce!=='string'||!hex.test(nonce)||o.getOwner(next)||next?.readyState!==1)throw Error('Invalid pending status actor');
  const username=o.getPendingOwner(next),id=o.getAccountId(username),candidate=o.getCandidateKey(next);publicKey(candidate);
  const row=read().accounts[id];if(!row||row.username!==username)return null;
  const item=row.certificates.find(x=>x.payload.transferNonce===nonce&&x.payload.newIdentityKey===candidate);if(!item)return null;
  return Object.freeze({accountId:id,epoch:item.payload.toEpoch,committed:true,isCurrent:row.identityKey===candidate&&row.epoch===item.payload.toEpoch});
 }
 function certificates(accountId,fromEpoch,limit=32){
  if(typeof accountId!=='string'||!uuid.test(accountId)||!Number.isSafeInteger(fromEpoch)||fromEpoch<0||!Number.isInteger(limit)||limit<1||limit>32)throw Error('Invalid certificate page');
  fresh();const row=state.accounts[accountId];if(!row)return[];return clone(row.certificates.slice(fromEpoch,fromEpoch+limit));
 }
 function cancel(socket,nonce){const target=staged.has(socket)?socket:owners.get(o.getOwner(socket)),r=staged.get(target);
  if(!r||(socket!==target&&socket!==r.old))return;if(r.cert.payload.transferNonce!==nonce)throw Error('Cancellation nonce differs');drop(target);}
 function head(accountId){if(typeof accountId!=='string'||!uuid.test(accountId))throw Error('Invalid account ID');const row=read().accounts[accountId];return row?Object.freeze({accountId,username:row.username,epoch:row.epoch,identityKey:row.identityKey}):null;}
 return Object.freeze({stage,commit,status,certificates,cancel,head,get pendingCount(){prune(time());return staged.size;}});
}
module.exports={createDeviceTransitionLedger};
