'use strict';
const {createHash}=require('node:crypto');
const {createTransferChallenges}=require('./server_device_transfer_challenges');
function createDeviceTransferTransport(o){
  const pending=new Map(), owners=new Map();
  const now=o.now||Date.now, max=o.maxPending??64;
  if(!Number.isInteger(max)||max<1||max>1000)throw Error('Invalid capacity');
  const hash=b=>createHash('sha256').update(b).digest('hex');
  const challenges=createTransferChallenges({getOwner:o.getOwner,getActiveSocket:o.getActiveSocket,getAccountId:o.getAccountId,getPendingOwner:s=>pending.get(s)?.username,getCandidateHash:s=>pending.get(s)?.candidateHash,now,maxPending:max});
  function drop(s){const r=pending.get(s);if(!r)return;pending.delete(s);if(owners.get(r.username)===s)owners.delete(r.username);s.removeListener('close',r.close);try{challenges.cancel(r.old,r.challenge.nonce);}catch(_){}}
  function prune(){const t=now();for(const [s,r]of pending)if(t>=r.challenge.expiresAt||s.readyState!==1||o.getActiveSocket(r.username)!==r.old)drop(s);}
  function begin(s,{username,accountId,newIdentityKey}){
    prune();
    if(o.getOwner(s)||s.readyState!==1||typeof newIdentityKey!=='string')throw Error('Invalid pending socket');
    const key=Buffer.from(newIdentityKey,'base64');
    if(key.length!==33||key[0]!==5||key.toString('base64')!==newIdentityKey)throw Error('Invalid candidate key');
    const old=o.getActiveSocket(username);
    if(!old||old===s||old.readyState!==1||o.getOwner(old)!==username||o.getAccountId(username)!==accountId)throw Error('Old device unavailable');
    const previous=owners.get(username);
    if(!previous&&!pending.has(s)&&pending.size>=max)throw Error('Capacity reached');
    if(previous)drop(previous);drop(s);
    const r={username,old,newIdentityKey,candidateHash:hash(key),stamp:o.getCredentialStamp(username),close:()=>drop(s)};
    pending.set(s,r);owners.set(username,s);
    try{r.challenge=challenges.begin(old,s);s.once('close',r.close);o.send(old,'device_transfer_requested',{...r.challenge,username,newIdentityKey});o.send(s,'device_transfer_pending',{...r.challenge,username,newIdentityKey});}
    catch(e){drop(s);throw e;}
  }
  function relay(old,data){
    prune();const username=o.getOwner(old),s=owners.get(username),r=pending.get(s);
    if(!r||old!==r.old||o.getActiveSocket(username)!==old||o.getCredentialStamp(username)!==r.stamp){if(s)drop(s);throw Error('Transfer context changed');}
    const payload=data?.payload,signature=data?.signature;
    const fields=['purpose','accountId','username','oldIdentityHash','newIdentityKey','candidateHash','nonce','issuedAt','expiresAt'];
    if(!payload||typeof payload!=='object'||Array.isArray(payload)||Object.keys(payload).length!==fields.length||fields.some(k=>!Object.hasOwn(payload,k))||typeof signature!=='string')throw Error('Invalid proof envelope');
    const sig=Buffer.from(signature,'base64');
    if(sig.length!==64||sig.toString('base64')!==signature||typeof payload.oldIdentityHash!=='string'||!/^[0-9a-f]{64}$/.test(payload.oldIdentityHash))throw Error('Invalid proof encoding');
    for(const k of Object.keys(r.challenge))if(payload[k]!==r.challenge[k])throw Error('Proof challenge mismatch');
    if(payload.username!==username||payload.newIdentityKey!==r.newIdentityKey)throw Error('Proof target mismatch');
    challenges.takeForVerification(old,payload.nonce);
    drop(s);
    // Relay only: the client must verify against its independently pinned old key.
    o.send(s,'device_transfer_proof_unverified',{payload,signature});
  }
  function cancel(s,nonce){prune();const target=pending.has(s)?s:owners.get(o.getOwner(s)),r=pending.get(target);if(!r||(s!==target&&r.old!==s))return;if(nonce!==undefined&&nonce!==r.challenge.nonce)throw Error('Cancellation challenge mismatch');drop(target);}
  return Object.freeze({begin,relay,cancel,get pendingCount(){prune();return pending.size;}});
}
module.exports={createDeviceTransferTransport};
