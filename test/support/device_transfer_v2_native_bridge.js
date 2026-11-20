'use strict';
// Test-only public protocol bridge. Never accepts or stores private Signal keys.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),readline=require('node:readline'),{EventEmitter}=require('node:events');
const {createDeviceTransferCoordinator}=require('../../server_device_transfer_coordinator');
const config=JSON.parse(process.argv[2]),dir=fs.mkdtempSync(path.join(os.tmpdir(),'fenyvo-native-v2-test-'));
function cleanup(){fs.rmSync(dir,{recursive:true,force:true});}
process.on('exit',cleanup);process.on('SIGTERM',()=>process.exit(0));
function socket(){const s=new EventEmitter();s.readyState=1;return s;}
const old=socket(),next=socket();let coordinator;
const emit=(type,data)=>process.stdout.write(JSON.stringify({type,data})+'\n');
coordinator=createDeviceTransferCoordinator({file:path.join(dir,'public-transitions.json'),singleWriter:true,
 getOwner:s=>s===old?config.username:null,getActiveSocket:()=>old,getAccountId:()=>config.accountId,
 getCurrentIdentity:()=>config.oldIdentityKey,getCredentialStamp:()=>'synthetic-native-test-only',canReadHistory:()=>false,
 send:(s,type,data)=>{if(s===next&&type==='device_transfer_pending_v2')emit('request',data);
  if(s===next&&type==='device_transfer_proof_v2_unverified')emit('proof',data);
  if(s===next&&type==='device_transfer_committed_v2')emit('committed',{...data,oldStillConnected:old.readyState===1});}});
const lines=readline.createInterface({input:process.stdin});
lines.on('line',line=>{try{const m=JSON.parse(line);if(m.op==='proof')coordinator.handle(old,'device_transfer_proof_v2',m.data);
 else if(m.op==='commit')coordinator.handle(next,'device_transfer_commit_v2',{transferNonce:m.transferNonce});
 else if(m.op==='close'){lines.close();}else throw Error('Unsupported test operation');
}catch(e){emit('error',{reason:e.message});}});
lines.on('close',()=>process.exit(0));
try{coordinator.begin(next,{username:config.username,accountId:config.accountId,newIdentityKey:config.newIdentityKey});}
catch(e){emit('error',{reason:e.message});lines.close();}
