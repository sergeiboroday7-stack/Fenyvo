# STEP 59: persistent candidate and old-device v2 proofs

Status: implementation and targeted tests supplied; Windows Flutter validation pending.
This is NOT a completed device-transfer feature or a release. All public flags remain OFF.

## Implemented scope
- Candidate private identity is sealed in platform secure storage before it can be used by a future v2 transport. Public views omit private bytes and are recursively immutable.
- Staging/resume is scoped to account name, stable account UUID and the old public pin received directly from the old device. A corrupt journal is retained and fails closed. No timeout/cancel API deletes the private candidate.
- Staged -> verified -> committed -> installed states persist. Native Signal signatures are rechecked when reading the journal and accepting a certificate. Installation requires both a matching signed certificate and a current commit receipt from the authenticated v2 transport.
- Installation fills an empty active identity slot or resumes the same key. It cannot overwrite another existing identity. Ordinary identity generation and transfer installation share an in-isolate per-owner mutex. Serialized key buffers are zeroed where the API permits; immutable encoded strings remain managed by Dart and secure-storage APIs.
- Old-device v2 requests reuse the explicit-consent UI and existing current-session guards. Confirmation signs both the short-lived approval domain and durable key-transition domain. V1 behavior is retained.
- A test-only Dart/Node bridge exercises native old-device signing against the actual STEP 58 coordinator/ledger module. Node receives public values and signatures only.

## Required integration contract (not wired in this step)
1. Stop ordinary login/reconnect/Signal bootstrap before opening v2 transfer on a new profile.
2. Obtain the old pin through the trusted direct channel; stage/resume private candidate BEFORE any prepare request.
3. Verify the live approval, nonce, deadline, candidate hash, durable certificate and exact current UI/account/session context. Store the verified durable certificate before sending commit.
4. On uncertainty retain the journal and query password-checked status for the same nonce/candidate. Do not interpret timeout as an uncommitted status. Only a fresh authoritative status with committed:false may clear a VERIFIED proof, retaining the same private candidate. Committed/installed states cannot be reset that way.
5. Store the current commit receipt, install the sealed candidate idempotently, then use the explicit v2 activation login. Never fall back to ordinary login after an uncertain activation.
6. Completion requires authenticated activation plus successful native bootstrap and matching durable bundle publication ACK. The existing early login_success notification alone is insufficient.

## Limits and pending work
The new-device screen/client still uses v1 and is not connected to these persistence/activation APIs. V2 UI remains disabled by default. Old-device send success is not a server ACK. New-device runtime integration, status recovery controller, contact certificate routing and physical Android/Windows tests remain pending.
The mutex protects one Dart isolate only; cross-process/isolate writers are not supported. A single profile writer must be enforced before enabling transfer. Secure storage writes use one JSON journal plus readback, not a multi-record atomic transaction; a crash after active-key write is resumed from the retained committed journal. This is not an independent cryptographic audit or a power-loss durability guarantee.
Late ciphertext for old sessions, history migration, lost-old-phone recovery and directory freshness/key-transparency policy are not solved by this step. No stronger security claim is made.

## Validation supplied
Native candidate persistence/mismatch/corruption/resume/concurrency tests, v1/v2 old-signature tests, consent/session tests and a synthetic public-protocol Node bridge. Regression checks cover the existing request parser, peer continuity transaction, v1/v2 recovery journal and Signal round trip. All secure-storage tests use mock storage; no real profile data is exported. Node bridge uses fake sockets, not production/TCP/full server bootstrap.
No server source, public deployment, website, GitHub, real credentials, real peer trust or real history is modified by this package.
