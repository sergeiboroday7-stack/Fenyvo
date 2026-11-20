'use strict';
const {test}=require('node:test'),a=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),vm=require('node:vm'),crypto=require('node:crypto'),{EventEmitter}=require('node:events'),{createRequire}=require('node:module');
const root=process.env.FENYVO_ROOT||path.resolve(__dirname,'..'),req=createRequire(path.join(root,'package.json'));
const source=fs.readFileSync(path.join(root,'server.js'),'utf8'),adapter=req('./server_account_identity_login');
const key=n=>Buffer.concat([Buffer.from([5]),Buffer.alloc(32,n)]).toString('base64'),hash=k=>crypto.createHash('sha256').update(Buffer.from(k,'base64')).digest('hex');
const id='11111111-1111-4111-8111-111111111111';
function between(start,end){const i=source.indexOf(start),j=source.indexOf(end,i+start.length);a.ok(i>=0&&j>i,'Source boundaries: '+start);return source.slice(i+start.length,j);}
const factory=between('// DEVICE_TRANSFER_V2_FACTORY_BEGIN','// DEVICE_TRANSFER_V2_FACTORY_END');
const routes=between('// DEVICE_TRANSFER_V2_ROUTES_BEGIN','// DEVICE_TRANSFER_V2_ROUTES_END');
const loginStart=source.search(/if\s*\(\s*type\s*===\s*'login'\s*\)\s*\{/),loginEnd=source.indexOf('// Existing accounts receive a soft migration prompt',loginStart);
a.ok(loginStart>=0&&loginEnd>loginStart);const login=source.slice(loginStart,loginEnd);
const publishStart=source.indexOf("          if (type === 'e2ee_publish_bundle') {"),publishEnd=source.indexOf("          if (type === 'e2ee_invite')",publishStart);
a.ok(publishStart>=0&&publishEnd>publishStart);const publication=source.slice(publishStart,publishEnd);
const ps=source.indexOf('function hashPassword('),pe=source.indexOf('function send(',ps);
const passwords=vm.runInNewContext(source.slice(ps,pe)+';({hashPassword,verifyPassword})',{crypto,Buffer});
class Socket extends EventEmitter{constructor(){super();this.readyState=1;this.messages=[];}close(){if(this.readyState!==1)return;this.readyState=3;this.emit('close');}}
async function fixture(enabled,body){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'fenyvo-v2-route-test-')),file=path.join(dir,'users.json'),password=await passwords.hashPassword('test-password-only');
 const users={Alice:{salt:password.salt,passwordHash:password.hash,accountId:id,contacts:['Bob']}},online=new Map(),identities=new WeakMap(),bundles={Alice:{identityKey:key(1)}},accepted=new Map([['Alice',['Bob']],['Bob',['Alice']]]),blocked=new Set();
 const bundleFile=path.join(dir,'e2ee_bundles.json');fs.writeFileSync(bundleFile,JSON.stringify(bundles));fs.writeFileSync(file,JSON.stringify(users));const old=new Socket();identities.set(old,'Alice');online.set('Alice',old);
 const ctx={require:req,path,console:{log(){},error(){}},Buffer,crypto,process:{env:{FENYVO_ACCOUNT_ID_ENABLED:'true',FENYVO_DEVICE_TRANSFER_V2_ENABLED:enabled?'true':'false'}},
  registeredUsers:users,USERS_FILE:file,E2EE_BUNDLES_FILE:bundleFile,e2eeBundles:bundles,onlineUsers:online,wsSessionIdentity:{getAuthenticatedUser:w=>identities.get(w),bindAuthenticated:(w,u)=>identities.set(w,u)},
  getAcceptedCommunicationContacts:u=>accepted.get(u)||[],isBlockedBy:(owner,peer)=>blocked.has(owner+':'+peer),prepareLoginAccountIdentity:adapter.prepareLoginAccountIdentity,accountIdentityError:adapter.accountIdentityError,
  verifyPassword:passwords.verifyPassword,consumeAuthAttempt:()=>({allowed:true}),clientAddress:'127.0.0.1',AUTH_DUMMY_SALT:'test-dummy',AUTH_DUMMY_HASH:crypto.scryptSync('dummy','test-dummy',64).toString('hex'),
  AUTH_ACCOUNT_RATE_LIMITER:{reset(){}},authAccountKey:()=>'',publicPresence:{bind(){}},mediaTokens:new Map(),createTurnCredentials:()=>null,hasCurrentLegalAcceptance:()=>true,
  MEDIA_PORT:0,MAX_MEDIA_BYTES:0,LEGAL_TERMS_VERSION:'test',LEGAL_PRIVACY_VERSION:'test',LEGAL_MINIMUM_AGE:16,broadcastUsers(){},broadcastUserStatus(){},deviceTransferTransport:{cancel(){}},
  send:(w,type,data)=>{if(w.readyState===1)w.messages.push(JSON.parse(JSON.stringify({type,data})));}};
 ctx.saveE2eeBundles=()=>fs.writeFileSync(bundleFile,JSON.stringify(bundles));
 const context=vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('function isBase64Value('),source.indexOf('function saveE2eeBundles(')),context);vm.runInContext(factory,context);
 const make=vm.runInContext('(function(ws){let currentUser=null;return async function(type,data){'+routes+login+publication+'};})',context);
 const create=()=>{const raw=new Socket(),handle=make(raw);return{raw,handle,login:data=>handle('login',{username:'Alice',password:'test-password-only',...data})};};
 const message=(socket,type)=>socket.messages.findLast(x=>x.type===type)?.data;
 const packet=next=>{const request=message(next,'device_transfer_pending_v2');a.ok(request);const {fromEpoch,...approval}=request;approval.oldIdentityHash=hash(bundles.Alice.identityKey);
  return{approval:{payload:approval,signature:Buffer.alloc(64,7).toString('base64')},certificate:{payload:{purpose:'fenyvo-device-key-transition-v1',accountId:id,username:'Alice',oldIdentityHash:approval.oldIdentityHash,newIdentityKey:approval.newIdentityKey,fromEpoch,toEpoch:fromEpoch+1,issuedAt:approval.issuedAt,transferNonce:approval.nonce},signature:Buffer.alloc(64,8).toString('base64')}};};
 const approve=async next=>{const currentOld=online.get('Alice'),handleOld=make(currentOld),proof=packet(next.raw);await handleOld('device_transfer_proof_v2',proof);a.ok(message(next.raw,'device_transfer_proof_v2_unverified'));return proof;};
 const transition=async (candidate,publish=true)=>{const next=create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:candidate});const proof=await approve(next);const nonce=proof.certificate.payload.transferNonce;
  await next.handle('device_transfer_commit_v2',{transferNonce:nonce});a.ok(message(next.raw,'device_transfer_committed_v2'));
  await next.login({mode:'device_transfer_activate_v2',newIdentityKey:candidate,transferNonce:nonce});a.equal(message(next.raw,'login_success')?.deviceTransferActivated,true);if(publish)bundles.Alice.identityKey=candidate;return{next,nonce,proof};};
 try{await body({dir,file,bundleFile,users,online,identities,bundles,accepted,blocked,old,create,message,packet,approve,transition,make,context});}
 finally{for(const socket of online.values())socket.close();fs.rmSync(dir,{recursive:true,force:true});}
}
test('default-off v2 login does not bind or disconnect existing session',()=>fixture(false,async f=>{const next=f.create(),before=fs.readFileSync(f.file);await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});a.ok(f.message(next.raw,'device_transfer_error_v2'));a.equal(f.identities.get(next.raw),undefined);a.equal(f.old.readyState,1);a.deepEqual(fs.readFileSync(f.file),before);a.equal(fs.existsSync(path.join(f.dir,'device_transitions_v1.json')),false);}));
test('wrong real password cannot enter the v2 coordinator',()=>fixture(true,async f=>{const next=f.create();await next.login({password:'wrong-test-password',mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});a.ok(f.message(next.raw,'login_error'));a.equal(f.old.readyState,1);a.equal(fs.existsSync(path.join(f.dir,'device_transitions_v1.json')),false);}));
test('unknown transfer login mode cannot fall through to ordinary login',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:'device_transfer_typo_v2',newIdentityKey:key(2)});a.equal(f.message(next.raw,'device_transfer_error_v2').code,'unsupported_mode');a.equal(f.message(next.raw,'login_success'),undefined);a.equal(f.old.readyState,1);}));
test('prepare and approval leave old device active and new device unauthenticated',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});a.equal(f.old.readyState,1);a.equal(f.identities.get(next.raw),undefined);await f.approve(next);a.equal(f.old.readyState,1);a.equal(f.identities.get(next.raw),undefined);a.equal(fs.existsSync(path.join(f.dir,'device_transitions_v1.json')),false);}));
test('commit then activation binds only the committed candidate and closes old session',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});const proof=await f.approve(next),nonce=proof.certificate.payload.transferNonce;
 await next.handle('device_transfer_commit_v2',{transferNonce:nonce});a.ok(f.message(next.raw,'device_transfer_committed_v2'));a.equal(f.old.readyState,1);a.equal(f.identities.get(next.raw),undefined);
 await next.login({mode:'device_transfer_activate_v2',newIdentityKey:key(2),transferNonce:nonce});a.equal(f.message(next.raw,'login_success').deviceTransferEpoch,1);a.equal(f.old.readyState,3);a.equal(f.online.get('Alice'),next.raw);a.equal(next.raw.__fenyvoTransferV2.identityKey,key(2));
 await next.handle('e2ee_publish_bundle',{identityKey:key(3)});a.equal(f.message(next.raw,'e2ee_bundle_published').ok,false);
}));
test('activation without durable commit is refused before old disconnect',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});const nonce=f.message(next.raw,'device_transfer_pending_v2').nonce;
 await next.login({mode:'device_transfer_activate_v2',newIdentityKey:key(2),transferNonce:nonce});a.ok(f.message(next.raw,'device_transfer_error_v2'));a.equal(f.identities.get(next.raw),undefined);a.equal(f.old.readyState,1);
}));
test('commit status and activation can resume after old device goes offline',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});const proof=await f.approve(next),nonce=proof.certificate.payload.transferNonce;
 await next.handle('device_transfer_commit_v2',{transferNonce:nonce});f.old.close();const resumed=f.create();await resumed.login({mode:'device_transfer_status_v2',newIdentityKey:key(2),transferNonce:nonce});a.equal(f.message(resumed.raw,'device_transfer_status_v2').isCurrent,true);
 await resumed.login({mode:'device_transfer_activate_v2',newIdentityKey:key(2),transferNonce:nonce});a.equal(f.message(resumed.raw,'login_success').deviceTransferEpoch,1);
}));
test('obsolete activation cannot disconnect the newer active phone',()=>fixture(true,async f=>{const first=await f.transition(key(2)),second=await f.transition(key(3)),replay=f.create();await replay.login({mode:'device_transfer_activate_v2',newIdentityKey:key(2),transferNonce:first.nonce});a.ok(f.message(replay.raw,'device_transfer_error_v2'));a.equal(second.next.raw.readyState,1);a.equal(f.online.get('Alice'),second.next.raw);}));
test('certificate retrieval uses accepted-contact policy and matching published identity',()=>fixture(true,async f=>{const transfer=await f.transition(key(2));const bob=new Socket(),eve=new Socket();f.identities.set(bob,'Bob');f.online.set('Bob',bob);f.identities.set(eve,'Eve');f.online.set('Eve',eve);
 await f.make(bob)('device_transfer_get_certificates_v2',{username:'Alice',fromEpoch:0,requestId:'f'.repeat(64)});const page=f.message(bob,'device_transfer_certificates_v2');a.equal(page.requestId,'f'.repeat(64));await f.make(bob)('device_transfer_get_certificates_v2',{username:'Alice',fromEpoch:0,requestId:'invalid'});a.ok(f.message(bob,'device_transfer_error_v2'));a.equal(page.available,true);a.equal(page.certificates.length,1);a.equal(page.certificates[0].payload.transferNonce,transfer.nonce);
 await f.make(eve)('device_transfer_get_certificates_v2',{username:'Alice',fromEpoch:0});a.ok(f.message(eve,'device_transfer_error_v2'));a.equal(f.message(eve,'device_transfer_certificates_v2'),undefined);
}));
test('coordinator refuses commit before approval and rejects invalid approval scope',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});const p=f.packet(next.raw),nonce=p.certificate.payload.transferNonce;
 await next.handle('device_transfer_commit_v2',{transferNonce:nonce});a.ok(f.message(next.raw,'device_transfer_error_v2'));p.approval.payload.oldIdentityHash='f'.repeat(64);await f.make(f.old)('device_transfer_proof_v2',p);a.ok(f.message(f.old,'device_transfer_error_v2'));a.equal(fs.existsSync(path.join(f.dir,'device_transitions_v1.json')),false);a.equal(f.old.readyState,1);
}));
test('ordinary login preserves legacy behavior with v2 off',()=>fixture(false,async f=>{const next=f.create();await next.login({});a.ok(f.message(next.raw,'login_success'));a.equal(f.message(next.raw,'login_success').deviceTransferActivated,undefined);a.equal(f.old.readyState,3);a.equal(fs.existsSync(path.join(f.dir,'device_transitions_v1.json')),false);}));

function publicBundle(identityKey){return{version:2,protocol:'signal-pqxdh-double-ratchet',deviceId:1,registrationId:42,identityKey,
 signedPreKey:{id:1,publicKey:key(4),signature:Buffer.alloc(64,7).toString('base64')},
 preKeys:[{id:1,publicKey:key(5)}],kyberPreKeys:[{id:1,publicKey:Buffer.alloc(1000,6).toString('base64'),signature:Buffer.alloc(64,8).toString('base64')}]};}
test('activated bundle write failure restores memory and disk before a safe retry',()=>fixture(true,async f=>{
 const transfer=await f.transition(key(2),false),beforeDisk=fs.readFileSync(f.bundleFile),beforeMemory=JSON.stringify(f.bundles),rename=fs.renameSync;
 fs.renameSync=(from,to)=>{if(to===f.bundleFile)throw Error('injected bundle rename failure');return rename(from,to);};
 try{await transfer.next.handle('e2ee_publish_bundle',publicBundle(key(2)));a.equal(f.message(transfer.next.raw,'e2ee_bundle_published').ok,false);a.equal(JSON.stringify(f.bundles),beforeMemory);a.deepEqual(fs.readFileSync(f.bundleFile),beforeDisk);}
 finally{fs.renameSync=rename;}
 await transfer.next.handle('e2ee_publish_bundle',publicBundle(key(2)));a.equal(f.message(transfer.next.raw,'e2ee_bundle_published').ok,true);a.equal(JSON.parse(fs.readFileSync(f.bundleFile)).Alice.identityKey,key(2));
}));

test('uncertain ledger readback recovers the durable commit before activation',()=>fixture(true,async f=>{
 const next=f.create();await next.login({mode:'device_transfer_prepare_v2',newIdentityKey:key(2)});const proof=await f.approve(next),nonce=proof.certificate.payload.transferNonce;
 const ledgerFile=path.join(f.dir,'device_transitions_v1.json'),read=fs.readFileSync;let fail=true;
 fs.readFileSync=(file,...args)=>{if(file===ledgerFile&&fail){fail=false;throw Error('injected one-time ledger readback failure');}return read(file,...args);};
 try{await next.handle('device_transfer_commit_v2',{transferNonce:nonce});a.ok(f.message(next.raw,'device_transfer_committed_v2'));}
 finally{fs.readFileSync=read;}
 await next.login({mode:'device_transfer_activate_v2',newIdentityKey:key(2),transferNonce:nonce});a.equal(f.message(next.raw,'login_success').deviceTransferEpoch,1);
}));

test('non-string transfer mode cannot become an ordinary login',()=>fixture(true,async f=>{const next=f.create();await next.login({mode:{value:'device_transfer_prepare_v2'},newIdentityKey:key(2)});a.ok(f.message(next.raw,'device_transfer_error_v2'));a.equal(f.message(next.raw,'login_success'),undefined);a.equal(f.old.readyState,1);}));
test('blocked accepted contact cannot fetch transition certificates',()=>fixture(true,async f=>{await f.transition(key(2));const bob=new Socket();f.identities.set(bob,'Bob');f.online.set('Bob',bob);f.blocked.add('Alice:Bob');await f.make(bob)('device_transfer_get_certificates_v2',{username:'Alice',fromEpoch:0});a.ok(f.message(bob,'device_transfer_error_v2'));a.equal(f.message(bob,'device_transfer_certificates_v2'),undefined);}));
