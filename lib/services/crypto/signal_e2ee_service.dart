import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:libsignal/libsignal.dart';
import 'package:synchronized/synchronized.dart';

import 'signal_secure_store.dart';

import 'package:crypto/crypto.dart' as transfer_hash;

import 'device_transfer_request.dart';
import 'old_device_pin.dart';
import 'device_key_transition.dart';
import 'device_transfer_approval.dart';

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
        throw StateError('Signal initialization is active for another account');
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
      await _ensureLibraryReady();

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

  Future<void>? _libraryInitialization;
  Future<void> _ensureLibraryReady() async {
    if (_libraryReady) return;
    final pending = _libraryInitialization;
    if (pending != null) {
      await pending;
      return;
    }
    final future = LibSignal.init();
    _libraryInitialization = future;
    try {
      await future;
      _libraryReady = true;
    } finally {
      if (identical(_libraryInitialization, future))
        _libraryInitialization = null;
    }
  }

  Future<String> publicIdentityKey() async {
    final identity = await _requireStore().ensureIdentity();
    return base64Encode(identity.publicKey);
  }

  Future<String> signIdentityMessage(Uint8List message) async {
    if (message.isEmpty) throw ArgumentError('Message is empty');
    final identity = await _requireStore().ensureIdentity();
    return base64Encode(identity.sign(message: message));
  }

  /// Memory-only candidate: no account, session or secure-store mutation.
  Future<void> prepareDeviceTransferCrypto() => _ensureLibraryReady();

  Future<IdentityKeyPair> createDeviceTransferCandidate() async {
    await _ensureLibraryReady();
    return IdentityKeyPair.generate();
  }

  Future<OldDevicePin> deviceTransferPublicPin({
    required String accountId,
    required String username,
    required bool Function() isSessionCurrent,
  }) async {
    if (!isReady || _username != username || !isSessionCurrent())
      throw StateError('Inactive account');
    final store = _requireStore(),
        identity = await _requireStore().readExistingIdentityForTransfer();
    try {
      if (!identical(store, _store) ||
          _username != username ||
          !isSessionCurrent())
        throw StateError('Account changed');
      return OldDevicePin.create(
        accountId: accountId,
        username: username,
        publicKey: identity.publicKey,
      );
    } finally {
      identity.dispose();
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
    await _processRemoteBundle(username, data, onlyIfMissing: false);
  }

  /// Returns whether a usable Double Ratchet session already exists.
  ///
  /// A published pre-key bundle is single-use. Fetching and processing a new
  /// bundle for every call would replace a healthy session and make messages
  /// and call signals encrypted on the previous ratchet intermittently fail.
  Future<bool> hasSession(String username) async {
    final remote = username.trim();
    if (remote.isEmpty || _store == null) return false;
    return _lockFor(remote).synchronized(() async {
      final address = ProtocolAddress(name: remote, deviceId: deviceId);
      return _requireStore().containsSession(address);
    });
  }

  /// Establishes a session from [data] only when another event has not
  /// already created one while the bundle request was in flight.
  Future<bool> processRemoteBundleIfMissing(
    String username,
    Map<String, dynamic> data,
  ) => _processRemoteBundle(username, data, onlyIfMissing: true);

  Future<bool> _processRemoteBundle(
    String username,
    Map<String, dynamic> data, {
    required bool onlyIfMissing,
  }) async {
    final remote = username.trim();
    if (remote.isEmpty) throw const FormatException('Missing remote user');
    return _lockFor(remote).synchronized(() async {
      final store = _requireStore();
      final remoteDeviceId = _positiveInt(data['deviceId']);
      final address = ProtocolAddress(name: remote, deviceId: remoteDeviceId);
      if (onlyIfMissing && await store.containsSession(address)) {
        return false;
      }
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
      await builder.processPreKeyBundle(address, bundle);
      return true;
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
        final signed = Map<String, dynamic>.from(
          bundleData['signedPreKey'] as Map,
        );
        final pre = Map<String, dynamic>.from(bundleData['preKey'] as Map);
        final kyber = Map<String, dynamic>.from(
          bundleData['kyberPreKey'] as Map,
        );
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
          address,
          originalSession,
          originalIdentity,
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

  /// Installs a new bundle only after continuity from the locally pinned key.
  /// Network routing remains disabled until the server transition flow is complete.
  Future<void> acceptContinuityVerifiedRemoteBundle(
    String username,
    Map<String, dynamic> bundleData, {
    required String expectedAccountId,
    required List<Map<String, dynamic>> certificates,
    required bool Function() isSessionCurrent,
  }) async {
    final remote = username.trim(), owner = _username;
    if (remote.isEmpty ||
        owner == null ||
        remote == owner ||
        certificates.isEmpty ||
        certificates.length > 32 ||
        !isSessionCurrent()) {
      throw StateError('Invalid continuity owner or session');
    }
    // Snapshot public inputs before entering an asynchronous lock.
    final encodedBundle = jsonEncode(bundleData),
        encodedCertificates = jsonEncode(certificates);
    if (encodedBundle.length > 32768 || encodedCertificates.length > 65536)
      throw StateError('Continuity payload too large');
    final bundleCopy = Map<String, dynamic>.from(
      jsonDecode(encodedBundle) as Map,
    );
    final certificateCopy = (jsonDecode(encodedCertificates) as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    await _verifiedRecoveryLock.synchronized(() async {
      await _lockFor(remote).synchronized(() async {
        final store = _requireStore();
        void check() {
          if (_username != owner ||
              !identical(store, _store) ||
              !isSessionCurrent()) {
            throw StateError('Continuity account or session changed');
          }
        }

        check();
        final address = ProtocolAddress(name: remote, deviceId: deviceId);
        final oldIdentity = await store.getIdentity(address);
        if (oldIdentity == null)
          throw StateError('Continuity requires a pinned old key');
        try {
          final oldSession = await store.loadSession(address),
              metadata = await store.readPeerContinuity(address);
          check();
          if (metadata != null &&
              (metadata['accountId'] != expectedAccountId ||
                  metadata['identityHash'] !=
                      transfer_hash.sha256
                          .convert(oldIdentity.serialize())
                          .toString())) {
            throw StateError(
              'Continuity metadata disagrees with existing trust',
            );
          }
          final chain = verifyDeviceKeyTransitionChain(
            certificates: certificateCopy,
            trustedOldIdentityKey: oldIdentity.serialize(),
            accountId: expectedAccountId,
            username: remote,
            storedEpoch: metadata?['epoch'] as int? ?? 0,
            nowMs: DateTime.now().millisecondsSinceEpoch,
          );
          if (chain == null ||
              bundleCopy['identityKey'] !=
                  base64Encode(chain.finalIdentityKey) ||
              _positiveInt(bundleCopy['deviceId']) != deviceId) {
            throw StateError('Certificate chain or bundle identity mismatch');
          }
          final signed = Map<String, dynamic>.from(
                bundleCopy['signedPreKey'] as Map,
              ),
              pre = Map<String, dynamic>.from(bundleCopy['preKey'] as Map),
              kyber = Map<String, dynamic>.from(
                bundleCopy['kyberPreKey'] as Map,
              );
          final bundle = PreKeyBundle(
            registrationId: _positiveInt(bundleCopy['registrationId']),
            deviceId: deviceId,
            preKeyId: _positiveInt(pre['id']),
            preKeyPublic: base64Decode(pre['publicKey'].toString()),
            signedPreKeyId: _positiveInt(signed['id']),
            signedPreKeyPublic: base64Decode(signed['publicKey'].toString()),
            signedPreKeySignature: base64Decode(signed['signature'].toString()),
            identityKey: chain.finalIdentityKey,
            kyberPreKeyId: _positiveInt(kyber['id']),
            kyberPreKeyPublic: base64Decode(kyber['publicKey'].toString()),
            kyberPreKeySignature: base64Decode(kyber['signature'].toString()),
          );
          check();
          await store.beginVerifiedPeerRecovery(
            address,
            oldSession,
            oldIdentity,
            preserveRetiredSession: true,
          );
          try {
            check();
            if (oldSession != null)
              await store.preserveRetiredPeerSession(
                address,
                oldSession,
                oldIdentity,
                accountId: expectedAccountId,
                fromEpoch: metadata?['epoch'] as int? ?? 0,
                toEpoch: chain.finalEpoch,
              );
            check();
            await store.deleteSession(address);
            check();
            await store.deleteRemoteIdentity(address);
            check();
            await SessionBuilder(
              localAddress: ProtocolAddress(name: owner, deviceId: deviceId),
              sessionStore: store,
              identityKeyStore: store,
            ).processPreKeyBundle(address, bundle);
            check();
            await store.saveVerifiedPeerContinuity(address, chain);
            check();
            await store.commitVerifiedPeerRecovery();
          } catch (_) {
            try {
              await store.restorePendingVerifiedPeerRecovery();
            } catch (_) {
              // A failed restore leaves a durable journal; block this store until recovery succeeds.
              if (identical(store, _store)) {
                _store = null;
                _username = null;
              }
              rethrow;
            }
            rethrow;
          }
        } finally {
          oldIdentity.dispose();
        }
      });
    });
  }

  Future<void> resetPeerRatchetSession(String username) async {
    final remote = username.trim();
    if (remote.isEmpty || _store == null) return;
    await _lockFor(remote).synchronized(() async {
      final address = ProtocolAddress(name: remote, deviceId: deviceId);
      await _store!.deleteSession(address);
    });
  }

  /// Clears ratchet state left by clients that recreated a session before
  /// every call. Long-term identities and pre-keys remain intact.
  Future<int> resetAllRatchetSessions() async {
    final store = _requireStore();
    final deleted = await store.deleteEverySession();
    _peerLocks.clear();
    return deleted;
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

  /// Explicit receive-only recovery; not wired into ordinary delivery or UI.
  Future<Map<String, dynamic>> decryptRetiredContactMessage(
    String username,
    Map<String, dynamic> envelope, {
    required bool Function() isSessionCurrent,
  }) async {
    final remote = username.trim();
    return _lockFor(remote).synchronized(() async {
      final store = _requireStore(), owner = _username;
      bool current() =>
          isSessionCurrent() && identical(store, _store) && owner == _username;
      if (!current() ||
          envelope['cipherType'] != 2 ||
          envelope['ciphertext'] is! String ||
          (envelope['ciphertext'] as String).length > 1048576)
        throw StateError('Retired receive not permitted');
      final decoded = await store.decryptRetiredPeerMessage(
        ProtocolAddress(name: remote, deviceId: deviceId),
        CiphertextMessage(
          type: CiphertextMessageType.fromValue(2),
          ciphertext: base64Decode(envelope['ciphertext'] as String),
        ),
        isCurrent: current,
      );
      if (!current()) throw StateError('Retired receive owner changed');
      final value = jsonDecode(utf8.decode(decoded));
      if (value is! Map)
        throw const FormatException('Invalid retired E2EE payload');
      return Map<String, dynamic>.from(value);
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
      unawaited(
        _ensurePreKeys().catchError((Object error, StackTrace stack) {
          // A failed background refill must not surface as an unhandled Future.
          // Awaited initialisation and bundle publishing still propagate errors.
          developer.log('Background PreKey refill failed', name: 'FENYVO_E2EE');
        }),
      );
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

  /// Public pinned peer state; never bootstraps identity or trust.
  Future<Map<String, dynamic>> contactContinuityHead(
    String peer, {
    required bool Function() isSessionCurrent,
  }) async {
    final owner = _username, store = _requireStore();
    void check() {
      if (!isSessionCurrent() ||
          owner != _username ||
          !identical(store, _store))
        throw StateError('Continuity owner changed');
    }

    check();
    final address = ProtocolAddress(name: peer, deviceId: deviceId);
    final identity = await store.getIdentity(address);
    try {
      final metadata = await store.readPeerContinuity(address);
      check();
      if (metadata != null && identity == null)
        throw StateError('Continuity metadata without pinned key');
      return {
        'identityKey': identity == null
            ? null
            : base64Encode(identity.serialize()),
        'epoch': metadata?['epoch'] ?? 0,
        'accountId': metadata?['accountId'],
      };
    } finally {
      identity?.dispose();
    }
  }

  /// Signs only an explicit, current request with the existing local identity.
  Future<Map<String, dynamic>> signConfirmedDeviceTransfer(
    DeviceTransferRequest request, {
    required bool userConfirmed,
    required bool Function() isSessionCurrent,
  }) async {
    if (!userConfirmed ||
        !isReady ||
        _username != request.username ||
        !isSessionCurrent() ||
        !request.validAt(DateTime.now().millisecondsSinceEpoch)) {
      throw StateError('Transfer approval is no longer current');
    }
    final store = _requireStore();
    final identity = await store.readExistingIdentityForTransfer();
    try {
      if (!identical(store, _store) ||
          _username != request.username ||
          !isSessionCurrent()) {
        throw StateError('Transfer account changed');
      }
      final payload = <String, dynamic>{
        ...request.data,
        'oldIdentityHash': transfer_hash.sha256
            .convert(identity.publicKey)
            .toString(),
      };
      final signature = signDeviceTransferApproval(
        payload: payload,
        identity: identity,
        accountId: request.accountId,
        username: request.username,
        newIdentityKey: request.newIdentityKey,
        nonce: request.nonce,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (!isSessionCurrent()) throw StateError('Transfer session changed');
      if (request.fromEpoch != null) {
        final epoch = request.fromEpoch!;
        final certificate = <String, dynamic>{
          'purpose': 'fenyvo-device-key-transition-v1',
          'accountId': request.accountId,
          'username': request.username,
          'oldIdentityHash': payload['oldIdentityHash'],
          'newIdentityKey': payload['newIdentityKey'],
          'fromEpoch': epoch,
          'toEpoch': epoch + 1,
          'issuedAt': payload['issuedAt'],
          'transferNonce': request.nonce,
        };
        final certificateSignature = signDeviceKeyTransition(
          payload: certificate,
          identity: identity,
          accountId: request.accountId,
          username: request.username,
          fromEpoch: epoch,
          newIdentityKey: request.newIdentityKey,
          transferNonce: request.nonce,
          nowMs: DateTime.now().millisecondsSinceEpoch,
          userConfirmed: userConfirmed,
        );
        if (!isSessionCurrent()) throw StateError('Transfer session changed');
        return {
          'approval': {'payload': payload, 'signature': signature},
          'certificate': {
            'payload': certificate,
            'signature': certificateSignature,
          },
        };
      }
      return {'payload': payload, 'signature': signature};
    } finally {
      identity.dispose();
    }
  }

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
