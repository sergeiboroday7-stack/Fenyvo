import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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
  final Lock _verifiedRecoveryLock = Lock();

  bool get isReady => _libraryReady && _store != null && _username != null;

  // Share initialization for the same account instead of returning early
  // while key generation or secure-store initialization is still running.
  Future<void>? _initializationInFlight;
  String? _initializingUser;

  Future<void> initializeForUser(String username) async {
    final user = username.trim();
    if (user.isEmpty) throw ArgumentError('Username is empty');

    final pending = _initializationInFlight;
    if (pending != null) {
      if (_initializingUser != user) {
        throw StateError(
          'Signal initialization is active for another account',
        );
      }
      await pending;
      return;
    }

    if (_libraryReady && _username == user && _store != null) {
      return;
    }

    final operation = _initializeForUserInternal(user);
    _initializingUser = user;
    _initializationInFlight = operation;

    try {
      await operation;
    } finally {
      if (identical(_initializationInFlight, operation)) {
        _initializationInFlight = null;
        _initializingUser = null;
      }
    }
  }

  Future<void> _initializeForUserInternal(String user) async {
    try {
      if (!_libraryReady) {
        await LibSignal.init();
        _libraryReady = true;
      }

      if (_username == user && _store != null) return;

      _username = user;
      _store = SignalSecureStore(user);
      await _store!.restorePendingVerifiedPeerRecovery();
      await _store!.ensureIdentity();
      await _store!.ensureRegistrationId();
      await _ensurePreKeys();
    } catch (_) {
      // Do not report a partially initialized store as ready.
      if (_username == user) {
        _username = null;
        _store = null;
      }
      rethrow;
    }
  }
  Lock _lockFor(String username) =>
      _peerLocks.putIfAbsent(username.trim(), Lock.new);

  Future<void>? _preKeyMaintenance;

  Future<void> _ensurePreKeys() async {
    final pending = _preKeyMaintenance;
    if (pending != null) {
      await pending;
      return;
    }
    final operation = _ensurePreKeysInternal();
    _preKeyMaintenance = operation;
    try {
      await operation;
    } finally {
      if (identical(_preKeyMaintenance, operation)) {
        _preKeyMaintenance = null;
      }
    }
  }

  Future<void> _ensurePreKeysInternal() async {
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

    while ((await store.getAllPreKeyIds()).length < _targetPreKeyCount) {
      final id = await store.reserveNextPreKeyId(kyber: false);
      final privateKey = PrivateKey.generate();
      await store.storePreKey(
        id,
        PreKeyRecord(
          id: id,
          publicKey: privateKey.getPublicKey(),
          privateKey: privateKey,
        ),
      );
    }

    while ((await store.getAllKyberPreKeyIds()).length < _targetPreKeyCount) {
      final id = await store.reserveNextPreKeyId(kyber: true);
      final keyPair = KyberKeyPair.generate();
      final publicKey = keyPair.getPublicKey();
      final signature = identity.sign(message: publicKey.serialize());
      await store.storeKyberPreKey(
        id,
        KyberPreKeyRecord.create(
          id: id,
          timestamp: now,
          keyPair: keyPair,
          signature: signature,
        ),
      );
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

  /// Preview a proposed remote identity without trusting or saving it.
  /// The caller must independently authenticate the candidate key before
  /// presenting an option to replace a previously verified identity.
  Future<E2eeSafetyNumber> candidateSafetyNumber(
    String username,
    String encodedRemoteIdentity,
  ) async {
    final remote = username.trim();
    final local = _username?.trim() ?? '';
    if (remote.isEmpty || local.isEmpty || remote == local) {
      throw StateError('E2EE identity is unavailable');
    }
    final candidateBytes = base64Decode(encodedRemoteIdentity);
    final candidate = PublicKey.deserialize(bytes: candidateBytes);
    final localIdentity = await _requireStore().ensureIdentity();
    final fingerprint = Fingerprint(
      iterations: 5200,
      version: 2,
      localIdentifier: utf8.encode(local),
      localPublicKey: localIdentity.publicKey,
      remoteIdentifier: utf8.encode(remote),
      remotePublicKey: candidate.serialize(),
    );
    final display = fingerprint.displayString().replaceAll(' ', '');
    final groups = <String>[];
    for (var i = 0; i < display.length; i += 5) {
      final end = i + 5 < display.length ? i + 5 : display.length;
      groups.add(display.substring(i, end));
    }
    return E2eeSafetyNumber(
      display: groups.join(' '),
      scannable:
          'spartan-e2ee:v1:${base64Url.encode(fingerprint.scannableEncoding())}',
    );
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

  /// Forgets a peer after the user explicitly disables protection for that
  /// chat. This is required when the peer reinstalled the app or changed
  /// phones and therefore has a new Signal identity.
  Future<void> resetPeerSession(String username) async {
    final remote = username.trim();
    if (remote.isEmpty || _store == null) return;
    await _lockFor(remote).synchronized(() async {
      final address = ProtocolAddress(name: remote, deviceId: deviceId);
      await _store!.deleteSession(address);
      await _store!.deleteRemoteIdentity(address);
    });
  }

  /// Changes a trusted remote identity only after explicit out-of-band
  /// comparison of the *candidate* safety number. This is never automatic.
  Future<void> acceptVerifiedRemoteBundle(
    String username,
    Map<String, dynamic> bundleData,
    String verifiedSafetyNumber,
  ) async {
    final remote = username.trim();
    final owner = _username?.trim() ?? '';
    if (remote.isEmpty || owner.isEmpty || remote == owner) {
      throw StateError('Invalid E2EE recovery owner or peer');
    }
    final encodedIdentity = bundleData['identityKey']?.toString() ?? '';
    if (encodedIdentity.isEmpty) {
      throw const FormatException('Missing candidate identity');
    }
    final comparison = await candidateSafetyNumber(remote, encodedIdentity);
    if (comparison.display != verifiedSafetyNumber ||
        verifiedSafetyNumber.replaceAll(' ', '').length != 60) {
      throw StateError('Candidate safety number was not confirmed');
    }

    await _verifiedRecoveryLock.synchronized(() async {
      await _lockFor(remote).synchronized(() async {
      if (_username != owner) throw StateError('Signal owner changed');
      final store = _requireStore();
      final address = ProtocolAddress(name: remote, deviceId: deviceId);
      final originalSession = await store.loadSession(address);
      final originalIdentity = await store.getIdentity(address);
      final signed = Map<String, dynamic>.from(bundleData['signedPreKey'] as Map);
      final pre = Map<String, dynamic>.from(bundleData['preKey'] as Map);
      final kyber = Map<String, dynamic>.from(bundleData['kyberPreKey'] as Map);
      final bundle = PreKeyBundle(
        registrationId: _positiveInt(bundleData['registrationId']),
        deviceId: _positiveInt(bundleData['deviceId']),
        preKeyId: _positiveInt(pre['id']),
        preKeyPublic: base64Decode(pre['publicKey'].toString()),
        signedPreKeyId: _positiveInt(signed['id']),
        signedPreKeyPublic: base64Decode(signed['publicKey'].toString()),
        signedPreKeySignature: base64Decode(signed['signature'].toString()),
        identityKey: base64Decode(encodedIdentity),
        kyberPreKeyId: _positiveInt(kyber['id']),
        kyberPreKeyPublic: base64Decode(kyber['publicKey'].toString()),
        kyberPreKeySignature: base64Decode(kyber['signature'].toString()),
      );
      if (_positiveInt(bundleData['deviceId']) != deviceId) {
        throw StateError('Unexpected E2EE peer device');
      }
      final current = await candidateSafetyNumber(remote, encodedIdentity);
      if (current.display != verifiedSafetyNumber) {
        throw StateError('Candidate identity changed during confirmation');
      }
      // Persist the pre-change state before the first destructive write.
      // An Android process death cannot run catch/finally; the initializer
      // restores this journal before making Signal usable again.
      await store.beginVerifiedPeerRecovery(
        address, originalSession, originalIdentity,
      );
      try {
        await store.deleteSession(address);
        await store.deleteRemoteIdentity(address);
        await SessionBuilder(
          localAddress: ProtocolAddress(name: owner, deviceId: deviceId),
          sessionStore: store,
          identityKeyStore: store,
        ).processPreKeyBundle(address, bundle);
        await store.commitVerifiedPeerRecovery();
      } catch (_) {
        await store.restorePendingVerifiedPeerRecovery();
        rethrow;
      }
      });
    });
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
      unawaited(_ensurePreKeys().catchError((Object error, StackTrace stack) {
        // A failed background refill must not surface as an unhandled Future.
        // Awaited initialisation and bundle publishing still propagate errors.
        developer.log('Background PreKey refill failed', name: 'FENYVO_E2EE');
      }));
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
