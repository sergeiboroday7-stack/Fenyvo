import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:libsignal/libsignal.dart';
import 'package:synchronized/synchronized.dart';

import 'signal_secure_store.dart';

class E2eeSessionMissing implements Exception {
  const E2eeSessionMissing(this.username);
  final String username;
}

class E2eeSafetyNumber {
  const E2eeSafetyNumber({required this.display, required this.scannable});

  final String display;
  final String scannable;
}

/// One-device Signal Protocol transport for private text messages.
///
/// The service never logs plaintext, keys, or ciphertext. Operations are
/// serialized per peer so two sends cannot advance the same ratchet in
/// parallel from an identical state.
class SignalE2eeService {
  SignalE2eeService._();

  static final instance = SignalE2eeService._();
  static const deviceId = 1;
  static const _targetPreKeyCount = 24;

  bool _libraryReady = false;
  String? _username;
  SignalSecureStore? _store;
  final Map<String, Lock> _peerLocks = <String, Lock>{};

  bool get isReady => _libraryReady && _store != null && _username != null;

  Future<void> initializeForUser(String username) async {
    final user = username.trim();
    if (user.isEmpty) throw ArgumentError('Username is empty');
    if (!_libraryReady) {
      await LibSignal.init();
      _libraryReady = true;
    }
    if (_username == user && _store != null) return;
    _username = user;
    _store = SignalSecureStore(user);
    await _store!.ensureIdentity();
    await _store!.ensureRegistrationId();
    await _ensurePreKeys();
  }

  Lock _lockFor(String username) =>
      _peerLocks.putIfAbsent(username.trim(), Lock.new);

  Future<void> _ensurePreKeys() async {
    final store = _requireStore();
    final identity = await store.ensureIdentity();
    final now = BigInt.from(DateTime.now().toUtc().millisecondsSinceEpoch);

    final signedIds = await store.getAllSignedPreKeyIds();
    if (signedIds.isEmpty) {
      final id = 1;
      final privateKey = PrivateKey.generate();
      final publicKey = privateKey.getPublicKey();
      final signature = identity.sign(message: publicKey.serialize());
      await store.storeSignedPreKey(
        id,
        SignedPreKeyRecord(
          id: id,
          timestamp: now,
          publicKey: publicKey,
          privateKey: privateKey,
          signature: signature,
        ),
      );
    }

    final preKeyIds = await store.getAllPreKeyIds();
    var nextPreKeyId = preKeyIds.isEmpty
        ? 1
        : preKeyIds.reduce((a, b) => a > b ? a : b) + 1;
    while ((await store.getAllPreKeyIds()).length < _targetPreKeyCount) {
      final privateKey = PrivateKey.generate();
      await store.storePreKey(
        nextPreKeyId,
        PreKeyRecord(
          id: nextPreKeyId,
          publicKey: privateKey.getPublicKey(),
          privateKey: privateKey,
        ),
      );
      nextPreKeyId++;
    }

    final kyberIds = await store.getAllKyberPreKeyIds();
    var nextKyberId = kyberIds.isEmpty
        ? 1
        : kyberIds.reduce((a, b) => a > b ? a : b) + 1;
    while ((await store.getAllKyberPreKeyIds()).length < _targetPreKeyCount) {
      final keyPair = KyberKeyPair.generate();
      final publicKey = keyPair.getPublicKey();
      final signature = identity.sign(message: publicKey.serialize());
      await store.storeKyberPreKey(
        nextKyberId,
        KyberPreKeyRecord.create(
          id: nextKyberId,
          timestamp: now,
          keyPair: keyPair,
          signature: signature,
        ),
      );
      nextKyberId++;
    }
  }

  Future<Map<String, dynamic>> createPublicBundle() async {
    await _ensurePreKeys();
    final store = _requireStore();
    final identity = await store.ensureIdentity();
    final signedId = (await store.getAllSignedPreKeyIds()).last;
    final signed = await store.loadSignedPreKey(signedId);
    if (signed == null) throw StateError('Signed pre-key missing');

    final preKeys = <Map<String, dynamic>>[];
    for (final id in await store.getAllPreKeyIds()) {
      final record = await store.loadPreKey(id);
      if (record != null) {
        preKeys.add({'id': id, 'publicKey': base64Encode(record.publicKey())});
      }
    }
    final kyberPreKeys = <Map<String, dynamic>>[];
    for (final id in await store.getAllKyberPreKeyIds()) {
      final record = await store.loadKyberPreKey(id);
      if (record != null) {
        kyberPreKeys.add({
          'id': id,
          'publicKey': base64Encode(record.getPublicKey().serialize()),
          'signature': base64Encode(record.signature()),
        });
      }
    }

    return {
      'protocol': 'signal-pqxdh-double-ratchet',
      'version': 2,
      'deviceId': deviceId,
      'registrationId': await store.ensureRegistrationId(),
      'identityKey': base64Encode(identity.publicKey),
      'signedPreKey': {
        'id': signedId,
        'publicKey': base64Encode(signed.publicKey()),
        'signature': base64Encode(signed.signature()),
      },
      'preKeys': preKeys,
      'kyberPreKeys': kyberPreKeys,
    };
  }

  Future<void> processRemoteBundle(
    String username,
    Map<String, dynamic> data,
  ) async {
    final remote = username.trim();
    if (remote.isEmpty) throw const FormatException('Missing remote user');
    await _lockFor(remote).synchronized(() async {
      final store = _requireStore();
      final signed = Map<String, dynamic>.from(data['signedPreKey'] as Map);
      final pre = Map<String, dynamic>.from(data['preKey'] as Map);
      final kyber = Map<String, dynamic>.from(data['kyberPreKey'] as Map);
      final bundle = PreKeyBundle(
        registrationId: _positiveInt(data['registrationId']),
        deviceId: _positiveInt(data['deviceId']),
        preKeyId: _positiveInt(pre['id']),
        preKeyPublic: base64Decode(pre['publicKey'].toString()),
        signedPreKeyId: _positiveInt(signed['id']),
        signedPreKeyPublic: base64Decode(signed['publicKey'].toString()),
        signedPreKeySignature: base64Decode(signed['signature'].toString()),
        identityKey: base64Decode(data['identityKey'].toString()),
        kyberPreKeyId: _positiveInt(kyber['id']),
        kyberPreKeyPublic: base64Decode(kyber['publicKey'].toString()),
        kyberPreKeySignature: base64Decode(kyber['signature'].toString()),
      );
      final builder = SessionBuilder(
        localAddress: ProtocolAddress(name: _username!, deviceId: deviceId),
        sessionStore: store,
        identityKeyStore: store,
      );
      await builder.processPreKeyBundle(
        ProtocolAddress(name: remote, deviceId: _positiveInt(data['deviceId'])),
        bundle,
      );
    });
  }

  Future<E2eeSafetyNumber> safetyNumber(String username) async {
    final remote = username.trim();
    final local = _username?.trim() ?? '';
    if (remote.isEmpty || local.isEmpty) {
      throw StateError('E2EE identity is unavailable');
    }
    final store = _requireStore();
    final localIdentity = await store.ensureIdentity();
    final remoteIdentity = await store.getIdentity(
      ProtocolAddress(name: remote, deviceId: deviceId),
    );
    if (remoteIdentity == null) {
      throw E2eeSessionMissing(remote);
    }
    final fingerprint = Fingerprint(
      iterations: 5200,
      version: 2,
      localIdentifier: utf8.encode(local),
      localPublicKey: localIdentity.publicKey,
      remoteIdentifier: utf8.encode(remote),
      remotePublicKey: remoteIdentity.serialize(),
    );
    final rawDisplay = fingerprint.displayString().replaceAll(' ', '');
    final groups = <String>[];
    for (var index = 0; index < rawDisplay.length; index += 5) {
      final end = index + 5 < rawDisplay.length ? index + 5 : rawDisplay.length;
      groups.add(rawDisplay.substring(index, end));
    }
    return E2eeSafetyNumber(
      display: groups.join(' '),
      scannable:
          'spartan-e2ee:v1:${base64Url.encode(fingerprint.scannableEncoding())}',
    );
  }

  Future<Map<String, dynamic>> encrypt(
    String username,
    Map<String, dynamic> plaintext,
  ) async {
    final remote = username.trim();
    return _lockFor(remote).synchronized(() async {
      final store = _requireStore();
      final address = ProtocolAddress(name: remote, deviceId: deviceId);
      if (!await store.containsSession(address)) {
        throw E2eeSessionMissing(remote);
      }
      final cipher = _cipher(store);
      final result = await cipher.encrypt(
        address,
        Uint8List.fromList(utf8.encode(jsonEncode(plaintext))),
      );
      return {
        'e2ee': true,
        'e2eeVersion': 2,
        'e2eeProtocol': 'signal',
        'cipherType': result.type.value,
        'ciphertext': base64Encode(result.ciphertext),
      };
    });
  }

  Future<Map<String, dynamic>> decrypt(
    String username,
    Map<String, dynamic> envelope,
  ) async {
    final remote = username.trim();
    return _lockFor(remote).synchronized(() async {
      final store = _requireStore();
      final rawType = int.tryParse(envelope['cipherType']?.toString() ?? '');
      final encoded = envelope['ciphertext']?.toString() ?? '';
      if (rawType == null || encoded.isEmpty) {
        throw const FormatException('Incomplete Signal envelope');
      }
      final ciphertext = CiphertextMessage(
        type: CiphertextMessageType.fromValue(rawType),
        ciphertext: base64Decode(encoded),
      );
      final decoded = await _cipher(
        store,
      ).decrypt(ProtocolAddress(name: remote, deviceId: deviceId), ciphertext);
      final value = jsonDecode(utf8.decode(decoded));
      if (value is! Map) throw const FormatException('Invalid E2EE payload');
      unawaited(_ensurePreKeys());
      return Map<String, dynamic>.from(value);
    });
  }

  SessionCipher _cipher(SignalSecureStore store) => SessionCipher(
    localAddress: ProtocolAddress(name: _username!, deviceId: deviceId),
    sessionStore: store,
    identityKeyStore: store,
    preKeyStore: store,
    signedPreKeyStore: store,
    kyberPreKeyStore: store,
  );

  SignalSecureStore _requireStore() {
    final store = _store;
    if (store == null || _username == null) {
      throw StateError('Signal E2EE is not initialized');
    }
    return store;
  }

  int _positiveInt(Object? value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      throw const FormatException('Invalid E2EE key id');
    }
    return parsed;
  }
}
