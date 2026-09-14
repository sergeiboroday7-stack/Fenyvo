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
    final changed = old == null || !old.equals(other: identityKey);
    await _writeBytes('remote_identity', id, identityKey.serialize());
    return changed;
  }

  @override
  Future<PublicKey?> getIdentity(ProtocolAddress address) async {
    final bytes = await _readBytes('remote_identity', _addressKey(address));
    return bytes == null ? null : PublicKey.deserialize(bytes: bytes);
  }

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
