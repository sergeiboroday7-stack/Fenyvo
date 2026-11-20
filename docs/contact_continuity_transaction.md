# Contact continuity transaction — local application API

Status: prepared for targeted native tests; no network routing or production flags enabled.

`SignalE2eeService.acceptContinuityVerifiedRemoteBundle` requires an existing
locally pinned old identity. It verifies a bounded signed certificate chain
against that key and the stored epoch/account binding. The final identity must
match the complete candidate pre-key bundle. Native Signal validates the bundle
signatures before the transaction commits.

The existing peer/global recovery locks protect the operation. Account/store
and caller session guards are checked around asynchronous operations. Inputs are
snapshotted and size-bounded before use. No `resetPeerSession` or unverified
key acceptance is used.

Recovery journal version 2 snapshots the peer identity, Signal session and
account-scoped continuity metadata before changes. The new metadata is saved
only after native pre-key processing succeeds. Journal deletion commits the
operation. A pending journal restores old key/session/metadata before Signal
initialization can continue; restore is retryable. Version 1 journals retain
their original recovery behavior. Corrupt version 2 snapshots fail closed and
remain available for recovery. A failed rollback disables the affected in-memory
store until initialization can restore its durable journal successfully.

A manually verified key change does not silently reset an existing certificate
counter. If continuity metadata no longer matches the manually pinned key,
automatic continuity is blocked until a separately trusted reconciliation path
is provided. Manual messaging remains governed by its existing flow.

This code does not touch Hive messages, credentials, contacts, files or account
identity. Tests use platform secure-storage mocks and generated temporary keys.
It does not install a new local phone identity, commit server epochs, distribute
certificates, enable network processing or publish a release.

Remaining integration includes durable server transition admission/commit,
new-device identity staging and activation, certificate delivery to offline
contacts, socket routing with generation guards and real Android/Windows tests.
Late messages encrypted for a retired session also require a reviewed policy
before enabling the complete transfer workflow. This block does not claim
end-to-end device transfer or preservation of all in-flight encrypted messages.
