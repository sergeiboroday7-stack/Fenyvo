'use strict';
const {createHash}=require('node:crypto');
const {createTransferChallenges}=require('./server_device_transfer_challenges');
const {createDeviceTransitionLedger}=require('./server_device_transition_ledger');
const hash=b=>createHash('sha256').update(b).digest('hex'),hex=/^[0-9a-f]{64}$/;
function publicKey(s){if(typeof s!=='string')throw Error('Invalid public key');const b=Buffer.from(s,'base64');if(b.length!==33||b[0]!==5||b.toString('base64')!==s)throw Error('Invalid public key');return b;}
function signature(s){if(typeof s!=='string')throw Error('Invalid signature encoding');const b=Buffer.from(s,'base64');if(b.length!==64||b.toString('base64')!==s)throw Error('Invalid signature encoding');}
function createDeviceTransferCoordinator(o){
 for(const k of ['getOwner','getActiveSocket','getAccountId','getCurrentIdentity','getCredentialStamp','canReadHistory','send'])if(typeof o?.[k]!=='function')throw Error('Required provider: '+k);
 const pending=new Map(),owners=new Map(),now=o.now||Date.now,max=o.maxPending??64;
 if(typeof now!=='function'||!Number.isInteger(max)||max<1||max>1000)throw Error('Invalid coordinator options');
 const time=()=>{const t=now();if(!Number.isSafeInteger(t)||t<0)throw Error('Invalid clock');return t;};
 const challenges=createTransferChallenges({getOwner:o.getOwner,getActiveSocket:o.getActiveSocket,getAccountId:o.getAccountId,
  getPendingOwner:s=>pending.get(s)?.username,getCandidateHash:s=>{const r=pending.get(s);return r?hash(publicKey(r.candidate)):null;},now,maxPending:max});
 const makeLedger=()=>createDeviceTransitionLedger({file:o.file,singleWriter:o.singleWriter,now,maxPending:max,
  getOwner:o.getOwner,getActiveSocket:o.getActiveSocket,getAccountId:o.getAccountId,getCurrentIdentity:o.getCurrentIdentity,getCredentialStamp:o.getCredentialStamp,
  getPendingOwner:s=>pending.get(s)?.username,getCandidateKey:s=>pending.get(s)?.candidate,getPendingChallenge:s=>pending.get(s)?.challenge,
  consumeChallenge:(old,next,nonce)=>{const r=pending.get(next);if(!r||r.old!==old||r.challenge?.nonce!==nonce)throw Error('Wrong challenge connection');return challenges.takeForVerification(old,nonce);},
  ...(o.writeAtomic?{writeAtomic:o.writeAtomic}:{})});
 let ledger=makeLedger();
 function release(s){const r=pending.get(s);if(!r)return;try{ledger.cancel(s,r.nonce);}catch(_){}if(r.old&&r.challenge)try{challenges.cancel(r.old,r.nonce);}catch(_){}
  pending.delete(s);if(owners.get(r.username)===s)owners.delete(r.username);s.removeListener('close',r.close);}
 function live(r){return r.next.readyState===1&&!o.getOwner(r.next)&&o.getAccountId(r.username)===r.accountId&&
  o.getCredentialStamp(r.username)===r.stamp&&(r.mode==='status'||r.committed||
  (r.old?.readyState===1&&o.getOwner(r.old)===r.username&&o.getActiveSocket(r.username)===r.old&&o.getCurrentIdentity(r.username)===r.oldKey));}
 function prune(){const t=time();for(const[s,r]of pending)if(t>=r.expiresAt||!live(r))release(s);}
 function context(next,data,mode){
  prune();publicKey(data.newIdentityKey);
  const {username,accountId}=data,stamp=o.getCredentialStamp(username);
  if(next?.readyState!==1||o.getOwner(next)||typeof username!=='string'||!username||username!==username.trim()||o.getAccountId(username)!==accountId||typeof accountId!=='string'||typeof stamp!=='string'||!stamp)throw Error('Invalid pending login context');
  const previous=owners.get(username);if(!previous&&!pending.has(next)&&pending.size>=max)throw Error('Pending capacity reached');
  return {next,username,accountId,candidate:data.newIdentityKey,stamp,mode,committed:false,approved:false,close:()=>release(next)};
 }
 function install(r){const previous=owners.get(r.username);if(previous)release(previous);release(r.next);pending.set(r.next,r);owners.set(r.username,r.next);r.next.once('close',r.close);}
 function begin(next,data){
  const r=context(next,data,'prepare'),old=o.getActiveSocket(r.username),oldKey=o.getCurrentIdentity(r.username),head=ledger.head(r.accountId);
  publicKey(oldKey);if(!old||old===next||old.readyState!==1||o.getOwner(old)!==r.username||oldKey===r.candidate||
   (head&&(head.username!==r.username||head.identityKey!==oldKey)))throw Error('Old device or directory head unavailable');
  r.old=old;r.oldKey=oldKey;r.fromEpoch=head?.epoch??0;
  // getPendingOwner must already identify this exact pending socket for challenge creation.
  install(r);
  try{r.challenge=challenges.begin(old,next);r.nonce=r.challenge.nonce;r.expiresAt=r.challenge.expiresAt;
   const data={...r.challenge,username:r.username,newIdentityKey:r.candidate,fromEpoch:r.fromEpoch};
   o.send(next,'device_transfer_pending_v2',data);o.send(old,'device_transfer_requested_v2',data);
  }catch(e){release(next);throw e;}
 }
 function statusLogin(next,data){
  if(typeof data.transferNonce!=='string'||!hex.test(data.transferNonce))throw Error('Invalid status nonce');
  const r=context(next,data,'status');r.nonce=data.transferNonce;r.expiresAt=time()+120000;install(r);
  const status=ledger.status(next,r.nonce);o.send(next,'device_transfer_status_v2',status??{committed:false});return status;
 }
 function proof(old,data){
  prune();const username=o.getOwner(old),r=pending.get(owners.get(username));
  if(!r||r.mode!=='prepare'||r.old!==old||r.approved||!live(r))throw Error('Approval context unavailable');
  if(!data||Object.keys(data).length!==2||!data.approval||!data.certificate)throw Error('Invalid proof fields');
  const approval=data.approval,p=approval.payload,cert=data.certificate,fields=['purpose','accountId','username','oldIdentityHash','newIdentityKey','candidateHash','nonce','issuedAt','expiresAt'];
  if(!p||typeof p!=='object'||Array.isArray(p)||Object.keys(p).length!==fields.length||fields.some(k=>!Object.hasOwn(p,k)))throw Error('Invalid approval payload');
  if(Object.keys(approval).length!==2||!Object.hasOwn(approval,'payload')||!Object.hasOwn(approval,'signature'))throw Error('Invalid approval envelope');
  signature(approval.signature);for(const k of Object.keys(r.challenge))if(p[k]!==r.challenge[k])throw Error('Approval challenge differs');
  if(p.username!==r.username||p.newIdentityKey!==r.candidate||p.oldIdentityHash!==hash(publicKey(r.oldKey))||
    cert.payload?.fromEpoch!==r.fromEpoch||cert.payload?.transferNonce!==r.nonce)throw Error('Approval target differs');
  ledger.stage(old,r.next,cert);r.approved=true;
  // Signal signatures remain opaque here: both clients must verify them independently.
  o.send(r.next,'device_transfer_proof_v2_unverified',{approval:JSON.parse(JSON.stringify(approval)),certificate:JSON.parse(JSON.stringify(cert))});
  o.send(old,'device_transfer_approved_v2',{transferNonce:r.nonce});
 }
 function commit(next,nonce){
  prune();const r=pending.get(next);if(!r||!r.approved||r.nonce!==nonce||!live(r))throw Error('Commit context unavailable');
  let result;
  try{result=ledger.commit(next,nonce);}catch(error){
   const durable=ledger.status(next,nonce);if(!durable?.committed||!durable.isCurrent)throw error;
   // Durable rename succeeded but acknowledgement was uncertain. Invalidate other staged approvals.
   for(const other of pending.values())try{ledger.cancel(other.next,other.nonce);}catch(_){}
   ledger=makeLedger();
   for(const other of [...pending.values()])if(other!==r&&other.approved&&!other.committed){o.send(other.next,'device_transfer_error_v2',{code:'retry_required'});release(other.next);}
   result={...durable,transferNonce:nonce};
  }
  r.committed=true;o.send(next,'device_transfer_committed_v2',result);return result;
 }
 function getStatus(next,nonce){prune();const r=pending.get(next);if(!r||!live(r)||typeof nonce!=='string'||!hex.test(nonce))throw Error('Status context unavailable');const result=ledger.status(next,nonce);o.send(next,'device_transfer_status_v2',result??{committed:false});return result;}
 function authorizeActivation(next,data){
  const r=context(next,data,'status');if(typeof data.transferNonce!=='string'||!hex.test(data.transferNonce))throw Error('Invalid activation nonce');
  r.nonce=data.transferNonce;r.expiresAt=time()+120000;install(r);
  const status=ledger.status(next,r.nonce);
  if(!status?.committed||!status.isCurrent){release(next);throw Error('Transition not current');}
  return Object.freeze({accountId:r.accountId,epoch:status.epoch,identityKey:r.candidate});
 }
 function checkPublication(actor,identityKey,activation){
  if(!activation)return true;const owner=o.getOwner(actor),head=ledger.head(activation.accountId);
  if(!owner||o.getActiveSocket(owner)!==actor||o.getAccountId(owner)!==activation.accountId||head?.username!==owner||head.epoch!==activation.epoch||
    head.identityKey!==identityKey||identityKey!==activation.identityKey)throw Error('Activated bundle identity differs');
  return true;
 }
 function getCertificates(actor,data){
  const viewer=o.getOwner(actor),subject=data.username;
  if(data.requestId!==undefined&&(typeof data.requestId!=='string'||!/^[0-9a-f]{64}$/.test(data.requestId)))throw Error('Invalid certificate request correlation');
  if(!viewer||o.getActiveSocket(viewer)!==actor||typeof subject!=='string'||!subject||!o.canReadHistory(viewer,subject))throw Error('Certificate access denied');
  const accountId=o.getAccountId(subject),head=ledger.head(accountId),from=data.fromEpoch??0;
  if(!Number.isSafeInteger(from)||from<0)throw Error('Invalid certificate offset');
  const available=!!head&&head.username===subject&&head.identityKey===o.getCurrentIdentity(subject);
  const certificates=available?ledger.certificates(accountId,from,32):[];
  o.send(actor,'device_transfer_certificates_v2',{...(data.requestId===undefined?{}:{requestId:data.requestId}),username:subject,accountId,available,fromEpoch:from,
    toEpoch:certificates.at(-1)?.payload.toEpoch??from,currentEpoch:head?.epoch??0,certificates});
 }
 function handle(actor,type,data={}){
  if(type==='device_transfer_proof_v2')return proof(actor,data);
  if(type==='device_transfer_commit_v2')return commit(actor,data.transferNonce);
  if(type==='device_transfer_get_status_v2')return getStatus(actor,data.transferNonce);
  if(type==='device_transfer_get_certificates_v2')return getCertificates(actor,data);
  if(type==='device_transfer_cancel_v2'){
   prune();const target=pending.has(actor)?actor:owners.get(o.getOwner(actor)),r=pending.get(target);
   if(!r||r.nonce!==data.transferNonce||(actor!==r.next&&actor!==r.old))throw Error('Cancellation context differs');
   if(r.committed)throw Error('Committed transition cannot be cancelled');release(target);return;
  }
  throw Error('Unsupported transfer route');
 }
 return Object.freeze({begin,statusLogin,authorizeActivation,checkPublication,handle,release,get pendingCount(){prune();return pending.size;}});
}
module.exports={createDeviceTransferCoordinator};
