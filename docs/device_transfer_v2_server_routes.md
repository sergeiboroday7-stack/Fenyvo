# Device transfer v2 — server routing and activation

Status: server coordinator is wired into the local server source. Disabled by
default. No production deployment or real-device transfer has been performed.

Both `FENYVO_DEVICE_TRANSFER_V2_ENABLED=true` and
`FENYVO_ACCOUNT_ID_ENABLED=true` are required. The v1 branch remains separate.
Do not enable v2 before implementing and checking the corresponding client flow.
The ledger remains an explicitly single-writer file store.

## Login modes

All modes pass through the existing password check, password-change race guard,
rate limiter and bound-account guard first.

- `device_transfer_prepare_v2`: creates a separate pending connection and a live
  challenge. The old authenticated socket stays active; the new socket is not
  authenticated as a chat session. Requests include the current directory epoch.
- `device_transfer_status_v2`: password-checked recovery/status query for a
  candidate key and transfer nonce; no active session is replaced.
- `device_transfer_activate_v2`: requires the exact durably committed current
  candidate and nonce before ordinary login binding/disconnection is allowed.
  `login_success` includes `deviceTransferActivated` and `deviceTransferEpoch`.
- Unknown reserved `device_transfer_*` modes fail closed rather than falling
  through to ordinary login. Disabled v2 modes cannot replace the old session.

## Events

Old-device request: `device_transfer_requested_v2`; pending response:
`device_transfer_pending_v2`. Data contain the existing challenge fields plus
username, newIdentityKey and fromEpoch.

`device_transfer_proof_v2` carries exactly `{approval, certificate}`. Approval
contains the v1 nine-field payload and signature. Certificate uses the separate
durable domain from STEP 55, bound to the same account, candidate, nonce, issuedAt
and current epoch. Node validates authenticated socket/context and encodings;
Signal signatures remain opaque and MUST be independently verified by clients.
The new device receives `device_transfer_proof_v2_unverified`. Directory staging
does not authenticate it or disconnect the old phone.

`device_transfer_commit_v2` uses transferNonce and the exact pending connection.
It records the public transition and replies `device_transfer_committed_v2`.
Cancellation cannot undo a committed transition. Uncertain durable readback is
resolved by status; other interrupted staged approvals require a fresh request.
`device_transfer_get_status_v2` replies `device_transfer_status_v2`.

`device_transfer_get_certificates_v2` requires an active authenticated viewer who
is the account owner or an accepted contact under the existing symmetric policy, with blocking respected in both directions.
It returns at most 32 certificates. A page is available only when the committed
head matches the currently published complete bundle identity.

## Public-key publication

An activated session is pinned to the committed candidate key/account/epoch.
`e2ee_publish_bundle` rejects another identity for that activated session. Its
publication uses the atomic JSON writer and restores the previous in-memory
record on failure, replying `ok:false` with a stable reasonCode. The old legacy
publication path is not globally changed by this block.

## Tests and limits

The new integration tests execute the actual updated login, route, factory and
publication bodies in a VM, using real scrypt verification, temporary JSON files
and test socket transports. They cover default-off behavior, wrong passwords,
reserved-mode fallback, old-session preservation, commit/activation, resume,
obsolete activation rejection, certificate privacy and atomic publication failure.
The ledger regression suite also runs because a read-only head API was added.
These tests are not a complete server bootstrap or TCP WebSocket/device test.
Dummy Signal signatures in Node fixtures test server authorization/storage only.

Still required: migrate old/new client UI and pending transport to v2; sign and
verify both proofs natively; durably stage the private candidate before sending a v2 prepare request, retain it
on cancellation/uncertain signed-certificate delivery, and install it without
overwriting an existing identity/history; handle commit uncertainty and login;
fetch/apply certificate chains with socket-generation guards; review late messages
for retired sessions; perform Android/Windows device checks before enabling or
publishing anything. This step does not complete the phone-transfer feature.
