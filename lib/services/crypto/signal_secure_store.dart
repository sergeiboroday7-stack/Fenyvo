import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal/libsignal.dart';

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

  Future<IdentityKeyPair> ensureIdentity() async {
    final encoded = await _readBytes('identity', 'pair');
    if (encoded != null) {
      try {
        return IdentityKeyPair.deserialize(bytes: encoded);
      } finally {
        encoded.fillRange(0, encoded.length, 0);
      }
    }
    final generated = IdentityKeyPair.generate();
    await _writeBytes('identity', 'pair', generated.serialize());
    return generated;
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

  /// Stores a crash-recovery snapshot *before* a verified identity change.
  /// Journal data stays inside the account-scoped platform secure storage.
  /// Only one verified recovery may be active at once.
  Future<void> beginVerifiedPeerRecovery(
    ProtocolAddress address,
    SessionRecord? oldSession,
    PublicKey? oldIdentity,
  ) async {
    final existing = await _read('verified_recovery', 'pending');
    if (existing != null) {
      throw StateError('Pending E2EE recovery must be restored first');
    }
    await _storage.write(
      key: _key('verified_recovery', 'pending'),
      value: jsonEncode(<String, Object?>{
        'version': 1,
        'peer': address.name(),
        'device': address.deviceId(),
        'session': oldSession == null ? null : base64Encode(oldSession.serialize()),
        'identity': oldIdentity == null ? null : base64Encode(oldIdentity.serialize()),
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
        data['version'] != 1 ||
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
    // Deserialize all snapshots before modifying any trusted state.
    final oldSession = sessionString == null
        ? null
        : SessionRecord.deserialize(bytes: base64Decode(sessionString as String));
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
    final next = [persisted, maximum, 1000000]
            .reduce((a, b) => a > b ? a : b) +
        1;
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
