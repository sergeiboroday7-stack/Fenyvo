# Device key transition certificate — local verification primitive

Status: implemented as a separate verifier/signer with targeted native tests.
It is not wired to production, account activation, contact trust or persistence.

The short-lived `fenyvo-device-transfer-v1` approval remains the authorization
for a particular pending request. It must not be repurposed as indefinite proof.
The separate `fenyvo-device-key-transition-v1` domain signs an ordered array:
purpose, accountId, username, oldIdentityHash, newIdentityKey, fromEpoch,
toEpoch, issuedAt, transferNonce. The prefix is
`FENYVO_DEVICE_KEY_TRANSITION_V1` followed by one NUL byte. UTF-8 JSON encoding
and canonical base64 are mandatory. Integer values must be JS-safe integers.

The signer checks explicit user confirmation, its own old key, account/name,
exact new key, prior epoch, transfer nonce and issuance time before signing.
No private key serialization, persistence or server upload occurs here.

Recipients must supply the previously pinned old public key and stored epoch
from local trusted state. The certificate must advance exactly one epoch and
change the key. Signature verification cannot establish trust in a server-supplied
old key. Unverified certificates must never be used to reset a Signal session.

Durable certificates deliberately have no request TTL. This permits offline
contacts to verify later. Replay protection is local monotonic epoch plus pinned
old key. A certificate cannot move a locally newer state backward, even if an
old key is reused. Chains are bounded to 32 links per verification call.
Every consecutive signature, account/name, old key and epoch must match.

Limitations: this does not prove the directory supplied the latest certificate,
prevent withholding of a suffix, establish an initial trust anchor or solve
compromise of a still-pinned signing key. It is not a key-transparency service.

Required before activation/integration:

- The old-device consent flow must sign both the pending approval and the
  durable certificate for the same account, candidate and nonce.
- The server must atomically commit exactly one transition for the current
  account epoch after the authenticated old-device approval, and retain public
  certificates for offline contacts. It must never receive private Signal keys.
- Local candidate identity installation must not overwrite an existing identity
  or history. Account activation needs crash recovery and explicit commit state.
- A receiving contact must verify continuity, match the complete new pre-key
  bundle, then atomically persist new pinned key, epoch and Signal session using
  rollback/recovery. An in-memory verification result alone is insufficient.
- Missing continuity or lost old device retains the existing manual trusted
  verification path; it must not trigger automatic trust.
- Full server/client flow, Android/Windows device tests and a targeted review
  are required before enabling flags or updating public builds.
