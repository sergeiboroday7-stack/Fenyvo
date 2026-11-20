# Server transition ledger — authenticated directory commit API

Status: local module and targeted storage/authorization tests. NOT wired to
server.js, WebSocket routes, phone activation or publication.

## Trust boundary

The server authorizes directory updates from the currently authenticated old
socket and a separately password-checked pending new socket. Required provider
functions must come from server-owned state, never request JSON. The challenge
consumer must enforce one-use and the exact old/new connection binding; the
existing challenge factory provides the underlying one-use primitive.

The ledger validates certificate structure, account/name, old published identity,
candidate identity, current epoch and live challenge nonce/time. Signal signatures
are OPAQUE public bytes here. Cryptographic verification remains mandatory on the
new device and each contact against an independently pinned old key. The Node
tests intentionally use dummy signature bytes; they do not claim Signal signature
verification. An authenticated account can submit invalid signature bytes and
damage its own directory continuity, but recipients must reject them.

## Prepare, commit and recovery

`stage(oldSocket, newSocket, certificate)` consumes the live challenge but does
not write the ledger or disconnect either device. One bounded pending record per
account is kept in memory, retaining exact socket, candidate and credential-stamp
bindings. Stamps remain in memory and are never serialized.

`commit(newSocket, nonce)` requires the same unexpired pending socket and all
original bindings, then atomically writes one public certificate and advances the
epoch exactly once. It uses the existing file-fsync/rename helper, checks readback
and rejects stale snapshots. A failed pre-rename write can be retried while the
authorization remains current. An uncertain result must not destroy the new
device's private candidate: `status` reads the durable file directly to determine
whether the same candidate/nonce was committed. Obsolete candidates are explicitly
marked `isCurrent: false`. A stale writer instance must be reloaded before further
writes; it must not overwrite the durable result.

Restart discards uncommitted socket authorizations. A fresh old-device approval
is then required. Completed public histories survive restart. History pages are
bounded to 32 certificates, compatible with the client chain verifier.

This is an explicitly SINGLE-WRITER file store. It is not a distributed lock,
multi-worker database, power-loss/directory-fsync guarantee or key-transparency
service. Multiple simultaneous writer processes are not supported. Sequential
stale instances are rejected, not silently merged. File and per-account history
size are bounded; there is no silent pruning of certificates needed by contacts.

## Required integration before enabling

- Adapt the pending transport to retain the new connection after receiving proof
  and to supply ledger providers from real authenticated/pending server state.
- Have the old-device consent flow sign the durable certificate for the current
  ledger epoch and the exact existing transfer challenge.
- The new device must verify both proofs and durably stage its private candidate
  locally before commit. Never upload that private key or overwrite a prior local
  identity/history. Handle commit uncertainty by status and guarded recovery.
- Bind active public-bundle publication to the committed candidate. A ledger
  record alone does not activate a bundle. Notify contacts only when the matching
  complete bundle is durably available; contacts still verify it cryptographically.
- Restrict certificate retrieval to the established authorized contact policy.
- Complete identity installation/login, late old-session message handling,
  certificate delivery/socket routing and real Android/Windows tests.

The module contains no production data path or automatic startup. Importing it
only defines functions. This step does not start Node server.js or change account
keys, Signal bundles, messages, website files, feature flags or GitHub.
