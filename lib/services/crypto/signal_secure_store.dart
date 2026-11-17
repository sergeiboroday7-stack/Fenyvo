import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal/libsignal.dart';
import 'package:synchronized/synchronized.dart';
import 'package:crypto/crypto.dart';

import 'device_key_transition.dart';

/// Persistent Signal Protocol stores backed by the platform secure store.
///
/// Every mutation awaits the platform write before returning because losing a
/// ratchet update can reuse message keys. One instance is scoped to one local
/// account so identities can never leak between accounts on a shared device.
class SignalSecureStore
    implements
        SessionStore,
        IdentityKeyStore,
        PreKeyStore,
        SignedPreKeyStore,
        KyberPreKeyStore {
  SignalSecureStore(this.localUsername);

  final String localUsername;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String get _scope => base64Url.encode(utf8.encode(localUsername.trim()));
  String _key(String kind, Object id) => 'spartan_signal_v2.$_scope.$kind.$id';
  String _addressKey(ProtocolAddress address) =>
      '${base64Url.encode(utf8.encode(address.name()))}.${address.deviceId()}';

  Future<String?> _read(String kind, Object id) =>
      _storage.read(key: _key(kind, id));

  Future<void> _writeBytes(String kind, Object id, List<int> bytes) async {
    final copy = Uint8List.fromList(bytes);
    try {
      await _storage.write(key: _key(kind, id), value: base64Encode(copy));
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  Future<Uint8List?> _readBytes(String kind, Object id) async {
    final value = await _read(kind, id);
    return value == null || value.isEmpty ? null : base64Decode(value);
  }

  Future<List<int>> _readIds(String kind) async {
    final value = await _read('${kind}_index', 'all');
    if (value == null || value.isEmpty) return <int>[];
    final decoded = jsonDecode(value);
    return decoded is List
        ? decoded.map((item) => int.tryParse('$item')).whereType<int>().toList()
        : <int>[];
  }

  Future<void> _saveIds(String kind, Iterable<int> ids) => _storage.write(
    key: _key('${kind}_index', 'all'),
    value: jsonEncode(ids.toSet().toList()..sort()),
  );

  Future<void> _addId(String kind, int id) async {
    final ids = await _readIds(kind);
    if (!ids.contains(id)) ids.add(id);
    await _saveIds(kind, ids);
  }

  Future<void> _removeId(String kind, int id) async {
    final ids = await _readIds(kind)
      ..remove(id);
    await _saveIds(kind, ids);
  }

  /// Transfer approval must never generate a replacement for a missing key.
  Future<IdentityKeyPair> readExistingIdentityForTransfer() async {
    final encoded = await _readBytes('identity', 'pair');
    if (encoded == null)
      throw StateError('Existing Signal identity unavailable');
    try {
      return IdentityKeyPair.deserialize(bytes: encoded);
    } finally {
      encoded.fillRange(0, encoded.length, 0);
    }
  }

  static final Map<String, Lock> _identityLocks = <String, Lock>{};
  Lock get _identityLock =>
      _identityLocks.putIfAbsent(localUsername.trim(), Lock.new);

  /// Read-only fingerprint for transfer diagnosis. Private key bytes never
  /// leave this store and the temporary serialized value is zeroed.
  Future<String?> existingIdentityFingerprintForTransfer() =>
      _identityLock.synchronized(() async {
        final raw = await _readBytes('identity', 'pair');
        if (raw == null) return null;
        IdentityKeyPair? pair;
        try {
          pair = IdentityKeyPair.deserialize(bytes: raw);
          return sha256.convert(pair.publicKey).toString();
        } finally {
          raw.fillRange(0, raw.length, 0);
          pair?.dispose();
        }
      });

  Future<bool> hasLocalIdentity() => _identityLock.synchronized(
    () => _storage.containsKey(key: _key('identity', 'pair')),
  );

  Future<bool> canInstallTransferredIdentity(List<int> publicKey) =>
      _identityLock.synchronized(() async {
        final raw = await _readBytes('identity', 'pair');
        if (raw == null) return true;
        IdentityKeyPair? existing;
        try {
          existing = IdentityKeyPair.deserialize(bytes: raw);
          return base64Encode(existing.publicKey) == base64Encode(publicKey);
        } finally {
          raw.fillRange(0, raw.length, 0);
          existing?.dispose();
        }
      });

  /// Fills an empty identity slot or resumes the same candidate; never replaces another key.
  Future<void> installFreshTransferredIdentity(IdentityKeyPair candidate) =>
      _identityLock.synchronized(() async {
        if (localUsername.trim().isEmpty)
          throw StateError('Missing identity owner');
        final raw = await _readBytes('identity', 'pair');
        if (raw != null) {
          IdentityKeyPair? existing;
          try {
            existing = IdentityKeyPair.deserialize(bytes: raw);
            if (base64Encode(existing.publicKey) !=
                base64Encode(candidate.publicKey))
              throw StateError(
                'Existing local identity must not be overwritten',
              );
            return;
          } finally {
            raw.fillRange(0, raw.length, 0);
            existing?.dispose();
          }
        }
        final bytes = candidate.serialize();
        try {
          await _writeBytes('identity', 'pair', bytes);
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
        final stored = await _readBytes('identity', 'pair');
        if (stored == null)
          throw StateError('Transferred identity readback missing');
        IdentityKeyPair? installed;
        try {
          installed = IdentityKeyPair.deserialize(bytes: stored);
          if (base64Encode(installed.publicKey) !=
              base64Encode(candidate.publicKey))
            throw StateError('Transferred identity readback differs');
        } finally {
          stored.fillRange(0, stored.length, 0);
          installed?.dispose();
        }
      });

  Future<IdentityKeyPair> ensureIdentity() =>
      _identityLock.synchronized(_ensureIdentityUnlocked);

  Future<IdentityKeyPair> _ensureIdentityUnlocked() async {
    final encoded = await _readBytes('identity', 'pair');
    if (encoded != null) {
      try {
        return IdentityKeyPair.deserialize(bytes: encoded);
      } finally {
        encoded.fillRange(0, encoded.length, 0);
      }
    }
    final generated = IdentityKeyPair.generate();
    final bytes = generated.serialize();
    try {
      await _writeBytes('identity', 'pair', bytes);
      return generated;
    } catch (_) {
      generated.dispose();
      rethrow;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<int> ensureRegistrationId() async {
    final stored = int.tryParse(await _read('identity', 'registration') ?? '');
    if (stored != null && stored > 0) return stored;
    final generated = Random.secure().nextInt(16380) + 1;
    await _storage.write(
      key: _key('identity', 'registration'),
      value: generated.toString(),
    );
    return generated;
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() => ensureIdentity();

  @override
  Future<int> getLocalRegistrationId() => ensureRegistrationId();

  @override
  Future<bool> saveIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
  ) async {
    final id = _addressKey(address);
    final old = await getIdentity(address);
    if (old != null && !old.equals(other: identityKey)) {
      throw StateError(
        'Signal remote identity changed; explicit verification required',
      );
    }
    if (old == null) {
      await _writeBytes('remote_identity', id, identityKey.serialize());
      return true;
    }
    return false;
  }

  @override
  Future<PublicKey?> getIdentity(ProtocolAddress address) async {
    final bytes = await _readBytes('remote_identity', _addressKey(address));
    return bytes == null ? null : PublicKey.deserialize(bytes: bytes);
  }

  /// Removes only the remembered identity of one remote device.
  /// The local account identity is never touched.
  Future<void> deleteRemoteIdentity(ProtocolAddress address) =>
      _storage.delete(key: _key('remote_identity', _addressKey(address)));

  @override
  Future<bool> isTrustedIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
    Direction direction,
  ) async {
    final stored = await getIdentity(address);
    return stored == null || stored.equals(other: identityKey);
  }

  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) async {
    final bytes = await _readBytes('session', _addressKey(address));
    return bytes == null ? null : SessionRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storeSession(
    ProtocolAddress address,
    SessionRecord record,
  ) async {
    final id = _addressKey(address);
    await _writeBytes('session', id, record.serialize());
    final raw = await _read('session_names', 'all');
    final entries = raw == null
        ? <String>[]
        : List<String>.from(jsonDecode(raw));
    final value = '${address.name()}\u0000${address.deviceId()}';
    if (!entries.contains(value)) {
      entries.add(value);
      await _storage.write(
        key: _key('session_names', 'all'),
        value: jsonEncode(entries),
      );
    }
  }

  @override
  Future<bool> containsSession(ProtocolAddress address) =>
      _storage.containsKey(key: _key('session', _addressKey(address)));

  @override
  Future<void> deleteSession(ProtocolAddress address) =>
      _storage.delete(key: _key('session', _addressKey(address)));

  Map<String, dynamic> _decodePeerContinuity(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        data.length != 4 ||
        data['version'] != 1 ||
        data['accountId'] is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(data['accountId'] as String) ||
        data['epoch'] is! int ||
        (data['epoch'] as int) < 1 ||
        (data['epoch'] as int) > 9007199254740991 ||
        data['identityHash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(data['identityHash'] as String)) {
      throw StateError('Invalid peer continuity state');
    }
    return Map<String, dynamic>.unmodifiable(data);
  }

  Future<Map<String, dynamic>?> readPeerContinuity(
    ProtocolAddress address,
  ) async {
    final raw = await _read('peer_continuity', _addressKey(address));
    return raw == null ? null : _decodePeerContinuity(raw);
  }

  Future<void> saveVerifiedPeerContinuity(
    ProtocolAddress address,
    VerifiedDeviceKeyTransitionChain chain,
  ) async {
    if (chain.transitions.any(
          (item) => item.payload['username'] != address.name(),
        ) ||
        address.deviceId() != 1) {
      throw StateError('Continuity peer mismatch');
    }
    final identity = await getIdentity(address);
    if (identity == null) throw StateError('New peer identity is missing');
    try {
      if (base64Encode(identity.serialize()) !=
          base64Encode(chain.finalIdentityKey)) {
        throw StateError('New peer identity differs from certificate');
      }
      await _storage.write(
        key: _key('peer_continuity', _addressKey(address)),
        value: jsonEncode({
          'version': 1,
          'accountId': chain.transitions.last.payload['accountId'],
          'epoch': chain.finalEpoch,
          'identityHash': sha256.convert(chain.finalIdentityKey).toString(),
        }),
      );
    } finally {
      identity.dispose();
    }
  }

  Map<String, dynamic> _decodeRetiredArchive(String raw) {
    if (raw.length > 1048576) throw StateError('Retired archive too large');
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        value['version'] != 1 ||
        value['entries'] is! List ||
        (value['entries'] as List).length > 4)
      throw StateError('Invalid retired archive');
    for (final item in value['entries'] as List) {
      const fields = {
        'accountId',
        'fromEpoch',
        'toEpoch',
        'identity',
        'localHash',
        'session',
        'retiredAt',
      };
      if (item is! Map ||
          item.length != fields.length ||
          item.keys.any((k) => !fields.contains(k)) ||
          item['accountId'] is! String ||
          item['fromEpoch'] is! int ||
          item['toEpoch'] is! int ||
          item['fromEpoch'] < 0 ||
          item['toEpoch'] <= item['fromEpoch'] ||
          item['retiredAt'] is! int ||
          item['retiredAt'] < 0 ||
          item['localHash'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(item['localHash'] as String) ||
          item['identity'] is! String ||
          item['session'] is! String)
        throw StateError('Invalid retired entry');
      final key = PublicKey.deserialize(
        bytes: base64Decode(item['identity'] as String),
      );
      key.dispose();
      SessionRecord.deserialize(bytes: base64Decode(item['session'] as String));
    }
    return value;
  }

  /// Called only inside the journaled, certificate-verified continuity transaction.
  Future<void> preserveRetiredPeerSession(
    ProtocolAddress address,
    SessionRecord session,
    PublicKey identity, {
    required String accountId,
    required int fromEpoch,
    required int toEpoch,
  }) async {
    final raw = await _read('retired_sessions', _addressKey(address));
    final data = raw == null
        ? <String, dynamic>{'version': 1, 'entries': <dynamic>[]}
        : _decodeRetiredArchive(raw);
    final entries = data['entries'] as List;
    final local = await readExistingIdentityForTransfer();
    late String localHash;
    try {
      localHash = sha256.convert(local.publicKey).toString();
    } finally {
      local.dispose();
    }
    final key = base64Encode(identity.serialize());
    final index = entries.indexWhere(
      (e) =>
          e['accountId'] == accountId &&
          e['fromEpoch'] == fromEpoch &&
          e['identity'] == key &&
          e['localHash'] == localHash,
    );
    if (index < 0 && entries.length >= 4)
      throw StateError('Retired session retention capacity reached');
    final entry = {
      'accountId': accountId,
      'fromEpoch': fromEpoch,
      'toEpoch': toEpoch,
      'identity': key,
      'localHash': localHash,
      'session': base64Encode(session.serialize()),
      'retiredAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (index < 0) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    final encoded = jsonEncode(data);
    _decodeRetiredArchive(encoded);
    await _storage.write(
      key: _key('retired_sessions', _addressKey(address)),
      value: encoded,
    );
    if (await _read('retired_sessions', _addressKey(address)) != encoded)
      throw StateError('Retired session persistence not confirmed');
  }

  /// Explicit receive-only API. Caller must hold the peer lock. No active trust writes.
  /// Old authenticated traffic is not proof it was sent before retirement.
  Future<Uint8List> decryptRetiredPeerMessage(
    ProtocolAddress address,
    CiphertextMessage ciphertext, {
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!isCurrent()) throw StateError('Retired receive session changed');
    }

    check();
    if (ciphertext.type.value != 2)
      throw StateError('Retired pre-key messages are forbidden');
    final metadata = await readPeerContinuity(address);
    final raw = await _read('retired_sessions', _addressKey(address));
    final pinned = await getIdentity(address);
    try {
      if (metadata != null &&
          (pinned == null ||
              sha256.convert(pinned.serialize()).toString() !=
                  metadata['identityHash']))
        throw StateError('Active continuity trust differs');
    } finally {
      pinned?.dispose();
    }
    if (metadata == null || raw == null)
      throw StateError('Verified retired session unavailable');
    final data = _decodeRetiredArchive(raw),
        local = await readExistingIdentityForTransfer();
    late String localHash;
    try {
      localHash = sha256.convert(local.publicKey).toString();
    } finally {
      local.dispose();
    }
    final now = DateTime.now().millisecondsSinceEpoch,
        entries = data['entries'] as List;
    for (final entry in entries.reversed) {
      check();
      if (entry['accountId'] != metadata['accountId'] ||
          entry['toEpoch'] > metadata['epoch'] ||
          entry['localHash'] != localHash ||
          now < entry['retiredAt'] ||
          now - entry['retiredAt'] > 7 * 24 * 60 * 60 * 1000)
        continue;
      final memory = _RetiredReceiveStore(
        this,
        address,
        entry['identity'] as String,
        entry['session'] as String,
      );
      Uint8List decoded;
      try {
        decoded = await SessionCipher(
          localAddress: ProtocolAddress(name: localUsername, deviceId: 1),
          sessionStore: memory,
          identityKeyStore: memory,
          preKeyStore: memory,
          signedPreKeyStore: memory,
          kyberPreKeyStore: memory,
        ).decrypt(address, ciphertext);
      } catch (_) {
        continue;
      }
      check();
      if (await _read('retired_sessions', _addressKey(address)) != raw)
        throw StateError('Retired ratchet changed concurrently');
      entry['session'] = memory.session;
      final encoded = jsonEncode(data);
      await _storage.write(
        key: _key('retired_sessions', _addressKey(address)),
        value: encoded,
      );
      if (await _read('retired_sessions', _addressKey(address)) != encoded)
        throw StateError('Retired ratchet persistence not confirmed');
      check();
      return decoded;
    }
    throw StateError('No retained session authenticated this message');
  }

  /// Stores a crash-recovery snapshot *before* a verified identity change.
  /// Journal data stays inside the account-scoped platform secure storage.
  /// Only one verified recovery may be active at once.
  Future<void> beginVerifiedPeerRecovery(
    ProtocolAddress address,
    SessionRecord? oldSession,
    PublicKey? oldIdentity, {
    bool preserveRetiredSession = false,
  }) async {
    final existing = await _read('verified_recovery', 'pending');
    if (existing != null) {
      throw StateError('Pending E2EE recovery must be restored first');
    }
    final oldContinuity = await _read('peer_continuity', _addressKey(address));
    if (oldContinuity != null) _decodePeerContinuity(oldContinuity);
    final retired = preserveRetiredSession
        ? await _read('retired_sessions', _addressKey(address))
        : null;
    if (retired != null) _decodeRetiredArchive(retired);
    await _storage.write(
      key: _key('verified_recovery', 'pending'),
      value: jsonEncode(<String, Object?>{
        'version': preserveRetiredSession ? 3 : 2,
        if (preserveRetiredSession) 'retired': retired,
        'continuity': oldContinuity,
        'peer': address.name(),
        'device': address.deviceId(),
        'session': oldSession == null
            ? null
            : base64Encode(oldSession.serialize()),
        'identity': oldIdentity == null
            ? null
            : base64Encode(oldIdentity.serialize()),
      }),
    );
  }

  /// Repeated calls are safe after a process death halfway through restore.
  /// Never clear a journal until both old records are durable again.
  Future<void> restorePendingVerifiedPeerRecovery() async {
    final raw = await _read('verified_recovery', 'pending');
    if (raw == null) return;
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        (data['version'] != 1 &&
            data['version'] != 2 &&
            data['version'] != 3) ||
        data['peer'] is! String ||
        (data['peer'] as String).trim().isEmpty ||
        data['device'] is! int ||
        (data['device'] as int) <= 0) {
      throw StateError('Invalid pending E2EE recovery journal');
    }
    final sessionString = data['session'];
    final identityString = data['identity'];
    if ((sessionString != null && sessionString is! String) ||
        (identityString != null && identityString is! String)) {
      throw StateError('Invalid pending E2EE recovery snapshot');
    }
    final restoreContinuity = data['version'] == 2 || data['version'] == 3;
    if (data['version'] == 3) {
      if (!data.containsKey('retired') ||
          (data['retired'] != null && data['retired'] is! String))
        throw StateError('Invalid retired recovery snapshot');
      if (data['retired'] != null)
        _decodeRetiredArchive(data['retired'] as String);
    }
    final continuity = data['continuity'];
    if (restoreContinuity &&
        (!data.containsKey('continuity') ||
            (continuity != null && continuity is! String))) {
      throw StateError('Invalid continuity recovery snapshot');
    }
    if (restoreContinuity && continuity != null)
      _decodePeerContinuity(continuity as String);
    // Deserialize all snapshots before modifying any trusted state.
    final oldSession = sessionString == null
        ? null
        : SessionRecord.deserialize(
            bytes: base64Decode(sessionString as String),
          );
    final oldIdentity = identityString == null
        ? null
        : PublicKey.deserialize(bytes: base64Decode(identityString as String));
    final address = ProtocolAddress(
      name: data['peer'] as String,
      deviceId: data['device'] as int,
    );
    await deleteSession(address);
    await deleteRemoteIdentity(address);
    if (oldIdentity != null) await saveIdentity(address, oldIdentity);
    if (oldSession != null) await storeSession(address, oldSession);
    if (restoreContinuity) {
      if (continuity == null) {
        await _storage.delete(
          key: _key('peer_continuity', _addressKey(address)),
        );
      } else {
        await _storage.write(
          key: _key('peer_continuity', _addressKey(address)),
          value: continuity as String,
        );
      }
    }
    if (data['version'] == 3) {
      final key = _key('retired_sessions', _addressKey(address));
      if (data['retired'] == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: data['retired'] as String);
      }
    }
    await _storage.delete(key: _key('verified_recovery', 'pending'));
  }

  /// Commit only after successful prekey processing; an interrupted commit
  /// conservatively restores the previous trusted state on next startup.
  Future<void> commitVerifiedPeerRecovery() =>
      _storage.delete(key: _key('verified_recovery', 'pending'));

  @override
  Future<void> deleteAllSessions(String name) async {
    final raw = await _read('session_names', 'all');
    final entries = raw == null
        ? <String>[]
        : List<String>.from(jsonDecode(raw));
    final kept = <String>[];
    for (final entry in entries) {
      final parts = entry.split('\u0000');
      if (parts.length == 2 && parts.first == name) {
        final address = ProtocolAddress(
          name: parts.first,
          deviceId: int.tryParse(parts.last) ?? 1,
        );
        await deleteSession(address);
      } else {
        kept.add(entry);
      }
    }
    await _storage.write(
      key: _key('session_names', 'all'),
      value: jsonEncode(kept),
    );
  }

  /// Removes every Double Ratchet session for this local account while
  /// preserving the local identity, remote identities and pre-keys.
  Future<int> deleteEverySession() async {
    final raw = await _read('session_names', 'all');
    final entries = raw == null
        ? <String>[]
        : List<String>.from(jsonDecode(raw));
    var deleted = 0;
    for (final entry in entries) {
      final parts = entry.split('\u0000');
      if (parts.length != 2) continue;
      final device = int.tryParse(parts.last);
      if (device == null) continue;
      await deleteSession(ProtocolAddress(name: parts.first, deviceId: device));
      deleted++;
    }
    await _storage.write(key: _key('session_names', 'all'), value: '[]');
    return deleted;
  }

  @override
  Future<List<int>> getSubDeviceSessions(String name) async {
    final raw = await _read('session_names', 'all');
    final entries = raw == null
        ? <String>[]
        : List<String>.from(jsonDecode(raw));
    return entries
        .map((entry) => entry.split('\u0000'))
        .where((parts) => parts.length == 2 && parts.first == name)
        .map((parts) => int.tryParse(parts.last))
        .whereType<int>()
        .toList();
  }

  /// Reserve IDs durably before generating key material.
  /// Start above the legacy 1..N range to avoid reusing consumed IDs.
  Future<int> reserveNextPreKeyId({required bool kyber}) async {
    final kind = kyber ? 'kyber_prekey' : 'prekey';
    final persisted =
        int.tryParse(await _read('prekey_allocator', kind) ?? '') ?? 0;
    final existing = await _readIds(kind);
    final maximum = existing.isEmpty
        ? 0
        : existing.reduce((a, b) => a > b ? a : b);
    final next =
        [persisted, maximum, 1000000].reduce((a, b) => a > b ? a : b) + 1;
    if (next >= 0xFFFFFF) {
      throw StateError('Signal PreKey ID space exhausted');
    }
    await _storage.write(
      key: _key('prekey_allocator', kind),
      value: next.toString(),
    );
    return next;
  }

  @override
  Future<PreKeyRecord?> loadPreKey(int preKeyId) async {
    final bytes = await _readBytes('prekey', preKeyId);
    return bytes == null ? null : PreKeyRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storePreKey(int preKeyId, PreKeyRecord record) async {
    await _writeBytes('prekey', preKeyId, record.serialize());
    await _addId('prekey', preKeyId);
  }

  @override
  Future<bool> containsPreKey(int preKeyId) =>
      _storage.containsKey(key: _key('prekey', preKeyId));

  @override
  Future<void> removePreKey(int preKeyId) async {
    await _storage.delete(key: _key('prekey', preKeyId));
    await _removeId('prekey', preKeyId);
  }

  @override
  Future<List<int>> getAllPreKeyIds() => _readIds('prekey');

  @override
  Future<SignedPreKeyRecord?> loadSignedPreKey(int signedPreKeyId) async {
    final bytes = await _readBytes('signed_prekey', signedPreKeyId);
    return bytes == null ? null : SignedPreKeyRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storeSignedPreKey(
    int signedPreKeyId,
    SignedPreKeyRecord record,
  ) async {
    await _writeBytes('signed_prekey', signedPreKeyId, record.serialize());
    await _addId('signed_prekey', signedPreKeyId);
  }

  @override
  Future<bool> containsSignedPreKey(int signedPreKeyId) =>
      _storage.containsKey(key: _key('signed_prekey', signedPreKeyId));

  @override
  Future<void> removeSignedPreKey(int signedPreKeyId) async {
    await _storage.delete(key: _key('signed_prekey', signedPreKeyId));
    await _removeId('signed_prekey', signedPreKeyId);
  }

  @override
  Future<List<int>> getAllSignedPreKeyIds() => _readIds('signed_prekey');

  @override
  Future<KyberPreKeyRecord?> loadKyberPreKey(int kyberPreKeyId) async {
    final bytes = await _readBytes('kyber_prekey', kyberPreKeyId);
    return bytes == null ? null : KyberPreKeyRecord.deserialize(bytes: bytes);
  }

  @override
  Future<void> storeKyberPreKey(
    int kyberPreKeyId,
    KyberPreKeyRecord record,
  ) async {
    await _writeBytes('kyber_prekey', kyberPreKeyId, record.serialize());
    await _addId('kyber_prekey', kyberPreKeyId);
  }

  @override
  Future<bool> containsKyberPreKey(int kyberPreKeyId) =>
      _storage.containsKey(key: _key('kyber_prekey', kyberPreKeyId));

  @override
  Future<void> markKyberPreKeyUsed(
    int kyberPreKeyId,
    int signedPreKeyId,
    PublicKey baseKey,
  ) => removeKyberPreKey(kyberPreKeyId);

  @override
  Future<void> removeKyberPreKey(int kyberPreKeyId) async {
    await _storage.delete(key: _key('kyber_prekey', kyberPreKeyId));
    await _removeId('kyber_prekey', kyberPreKeyId);
  }

  @override
  Future<List<int>> getAllKyberPreKeyIds() => _readIds('kyber_prekey');
}

/// In-memory receive attempt: only the authenticated ratchet snapshot is committed.
class _RetiredReceiveStore extends SignalSecureStore {
  _RetiredReceiveStore(this.active, this.peer, this.identity, this.session)
    : super(active.localUsername);
  final SignalSecureStore active;
  final ProtocolAddress peer;
  final String identity;
  String session;
  void check(ProtocolAddress address) {
    if (address.name() != peer.name() || address.deviceId() != peer.deviceId())
      throw StateError('Retired peer differs');
  }

  @override
  Future<IdentityKeyPair> getIdentityKeyPair() =>
      active.readExistingIdentityForTransfer();
  @override
  Future<int> getLocalRegistrationId() async {
    final value = int.tryParse(
      await active._read('identity', 'registration') ?? '',
    );
    if (value == null || value <= 0)
      throw StateError('Existing registration missing');
    return value;
  }

  @override
  Future<PublicKey?> getIdentity(ProtocolAddress address) async {
    check(address);
    return PublicKey.deserialize(bytes: base64Decode(identity));
  }

  @override
  Future<bool> isTrustedIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
    Direction direction,
  ) async {
    check(address);
    return base64Encode(identityKey.serialize()) == identity;
  }

  @override
  Future<bool> saveIdentity(
    ProtocolAddress address,
    PublicKey identityKey,
  ) async {
    check(address);
    if (base64Encode(identityKey.serialize()) != identity)
      throw StateError('Retired trust replacement forbidden');
    return false;
  }

  @override
  Future<SessionRecord?> loadSession(ProtocolAddress address) async {
    check(address);
    return SessionRecord.deserialize(bytes: base64Decode(session));
  }

  @override
  Future<void> storeSession(
    ProtocolAddress address,
    SessionRecord record,
  ) async {
    check(address);
    session = base64Encode(record.serialize());
  }

  @override
  Future<bool> containsSession(ProtocolAddress address) async {
    check(address);
    return true;
  }

  @override
  Future<void> deleteSession(ProtocolAddress address) async {
    throw StateError('Retired deletion forbidden');
  }

  @override
  Future<void> deleteRemoteIdentity(ProtocolAddress address) async {
    throw StateError('Retired trust deletion forbidden');
  }
}
