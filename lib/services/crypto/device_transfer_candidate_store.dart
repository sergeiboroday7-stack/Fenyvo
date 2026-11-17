import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal/libsignal.dart';
import 'package:synchronized/synchronized.dart';

import 'device_key_transition.dart';
import 'old_device_pin.dart';
import 'signal_e2ee_service.dart';
import 'signal_secure_store.dart';

dynamic _readonly(dynamic value) {
  if (value is Map)
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, _readonly(v))),
    );
  if (value is List) return List<dynamic>.unmodifiable(value.map(_readonly));
  return value;
}

class PendingTransferCandidate {
  PendingTransferCandidate._(this.publicData);
  final Map<String, dynamic> publicData;
  String get username => publicData['username'] as String;
  String get accountId => publicData['accountId'] as String;
  String get identityKey => publicData['newIdentityKey'] as String;
  String get phase => publicData['phase'] as String;
  String? get transferNonce =>
      (publicData['certificate'] as Map?)?['payload']?['transferNonce']
          as String?;
}

/// One sealed candidate per local account. Never exports its private bytes.
/// The active identity is installed only after signed continuity and a matching commit receipt.
class DeviceTransferCandidateStore {
  DeviceTransferCandidateStore(String owner) : username = owner.trim() {
    if (username.isEmpty ||
        utf8.encode(username).length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(username))
      throw ArgumentError('Invalid candidate owner');
  }
  final String username;
  static final Map<String, Lock> _locks = <String, Lock>{};
  Lock get _lock => _locks.putIfAbsent(username, Lock.new);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String get _journal =>
      'fenyvo_transfer_v2.' +
      base64Url.encode(utf8.encode(username)) +
      '.candidate';
  SignalSecureStore get _active => SignalSecureStore(username);
  void _current(bool Function() check) {
    if (!check()) throw StateError('Transfer operation changed');
  }

  PendingTransferCandidate _view(Map<String, dynamic> record) {
    final public = Map<String, dynamic>.from(record)
      ..remove('privateIdentityPair');
    return PendingTransferCandidate._(
      _readonly(public) as Map<String, dynamic>,
    );
  }

  IdentityKeyPair _identity(Map<String, dynamic> record) {
    final raw = record['privateIdentityPair'];
    if (raw is! String) throw StateError('Invalid sealed candidate');
    final bytes = base64Decode(raw);
    IdentityKeyPair? identity;
    try {
      if (base64Encode(bytes) != raw)
        throw StateError('Noncanonical candidate');
      identity = IdentityKeyPair.deserialize(bytes: bytes);
      if (base64Encode(identity.publicKey) != record['newIdentityKey'])
        throw StateError('Candidate public/private binding differs');
      final key = PublicKey.deserialize(bytes: identity.publicKey);
      try {
        final message = utf8.encode(
          'FENYVO_LOCAL_CANDIDATE_SELF_CHECK_V1\u0000' +
              username +
              '\u0000' +
              (record['accountId'] as String),
        );
        if (!key.verify(
          message: message,
          signature: identity.sign(message: message),
        ))
          throw StateError('Candidate self-check failed');
      } finally {
        key.dispose();
      }
      return identity;
    } catch (_) {
      identity?.dispose();
      rethrow;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    await SignalE2eeService.instance.prepareDeviceTransferCrypto();
    String? raw;
    try {
      raw = await _storage.read(key: _journal);
    } catch (_) {
      throw StateError('Secure candidate read failed');
    }
    if (raw == null) return null;
    try {
      final r = jsonDecode(raw);
      const fields = {
        'version',
        'username',
        'accountId',
        'oldIdentityKey',
        'newIdentityKey',
        'privateIdentityPair',
        'phase',
        'certificate',
        'receipt',
      };
      if (r is! Map<String, dynamic> ||
          r.length != fields.length ||
          r.keys.any((k) => !fields.contains(k)) ||
          r['version'] != 1 ||
          r['username'] != username ||
          !{
            'staged',
            'verified',
            'committed',
            'installed',
          }.contains(r['phase']))
        throw StateError('Invalid candidate record');
      final pin = OldDevicePin.parse(
        jsonEncode({
          'purpose': 'fenyvo-transfer-old-device-pin-v1',
          'accountId': r['accountId'],
          'username': username,
          'identityKey': r['oldIdentityKey'],
        }),
      );
      final identity = _identity(r);
      identity.dispose();
      if (r['oldIdentityKey'] == r['newIdentityKey'])
        throw StateError('Candidate must change identity');
      final cert = r['certificate'], receipt = r['receipt'];
      if (r['phase'] == 'staged') {
        if (cert != null || receipt != null)
          throw StateError('Invalid staged state');
      } else {
        if (cert is! Map ||
            cert.length != 2 ||
            cert['payload'] is! Map ||
            cert['signature'] is! String)
          throw StateError('Missing signed candidate proof');
        final payload = Map<String, dynamic>.from(cert['payload'] as Map);
        final verified = verifyDeviceKeyTransition(
          payload: payload,
          signature: cert['signature'] as String,
          trustedOldIdentityKey: pin.publicKey,
          accountId: pin.accountId,
          username: username,
          storedEpoch: payload['fromEpoch'] as int,
          nowMs: payload['issuedAt'] as int,
        );
        if (verified == null ||
            base64Encode(verified.newIdentityKey) != r['newIdentityKey'])
          throw StateError('Stored candidate proof differs');
        if (r['phase'] == 'verified') {
          if (receipt != null) throw StateError('Unexpected commit receipt');
        } else if (receipt is! Map ||
            receipt.length != 5 ||
            receipt['accountId'] != r['accountId'] ||
            receipt['epoch'] != verified.toEpoch ||
            receipt['transferNonce'] != payload['transferNonce'] ||
            receipt['committed'] != true ||
            receipt['isCurrent'] != true)
          throw StateError('Invalid candidate commit receipt');
      }
      return r;
    } catch (_) {
      throw StateError('Sealed candidate invalid; preserve it for recovery');
    }
  }

  Future<void> _save(
    Map<String, dynamic> record,
    bool Function() current,
  ) async {
    _current(current);
    final encoded = jsonEncode(record);
    try {
      await _storage.write(key: _journal, value: encoded);
      if (await _storage.read(key: _journal) != encoded)
        throw StateError('readback');
    } catch (_) {
      throw StateError(
        'Secure candidate persistence failed; resume before retry',
      );
    }
    _current(current);
  }

  Future<void> _compatible(Map<String, dynamic> r) async {
    if (!await _active.canInstallTransferredIdentity(
      base64Decode(r['newIdentityKey'] as String),
    ))
      throw StateError('Existing local profile identity is protected');
  }

  /// Read-only comparison with the identity pinned in the old-phone code.
  /// This does not authorize transfer and performs no writes or network calls.
  Future<String> diagnoseExistingLocalIdentity(OldDevicePin pin) =>
      _lock.synchronized(() async {
        if (pin.username != username) return 'ACCOUNT_MISMATCH';
        await SignalE2eeService.instance.prepareDeviceTransferCrypto();
        final local = await _active.existingIdentityFingerprintForTransfer();
        if (local == null) return 'NO_LOCAL_IDENTITY';
        final old = sha256.convert(pin.publicKey).toString();
        return local == old ? 'MATCHES_OLD_DEVICE' : 'DIFFERS_FROM_OLD_DEVICE';
      });

  Future<PendingTransferCandidate?> readPublic() =>
      _lock.synchronized(() async {
        final r = await _load();
        if (r == null) return null;
        await _compatible(r);
        return _view(r);
      });
  Future<PendingTransferCandidate> createOrResume(
    OldDevicePin pin, {
    required bool Function() isOperationCurrent,
  }) => _lock.synchronized(() async {
    _current(isOperationCurrent);
    if (pin.username != username) throw StateError('Candidate account differs');
    final existing = await _load();
    if (existing != null) {
      if (existing['accountId'] != pin.accountId ||
          existing['oldIdentityKey'] != pin.identityKey)
        throw StateError('Existing candidate trust anchor differs');
      await _compatible(existing);
      _current(isOperationCurrent);
      return _view(existing);
    }
    if (await _active.hasLocalIdentity())
      throw StateError('Existing local profile identity is protected');
    _current(isOperationCurrent);
    final identity = await SignalE2eeService.instance
        .createDeviceTransferCandidate();
    try {
      final bytes = identity.serialize();
      late String encoded;
      try {
        encoded = base64Encode(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      final r = <String, dynamic>{
        'version': 1,
        'username': username,
        'accountId': pin.accountId,
        'oldIdentityKey': pin.identityKey,
        'newIdentityKey': base64Encode(identity.publicKey),
        'privateIdentityPair': encoded,
        'phase': 'staged',
        'certificate': null,
        'receipt': null,
      };
      if (r['newIdentityKey'] == pin.identityKey)
        throw StateError('Candidate identity unchanged');
      await _save(r, isOperationCurrent);
      await _compatible(r);
      _current(isOperationCurrent);
      return _view(r);
    } finally {
      identity.dispose();
    }
  });
  Future<PendingTransferCandidate> recordVerifiedCertificate(
    VerifiedDeviceKeyTransition certificate, {
    required String expectedTransferNonce,
    required bool Function() isOperationCurrent,
  }) => _lock.synchronized(() async {
    _current(isOperationCurrent);
    final r = await _load();
    if (r == null) throw StateError('Candidate missing');
    final p = Map<String, dynamic>.from(certificate.payload),
        certSignature = certificate.signature;
    if (p['accountId'] != r['accountId'] ||
        p['username'] != username ||
        p['oldIdentityHash'] !=
            sha256
                .convert(base64Decode(r['oldIdentityKey'] as String))
                .toString() ||
        p['newIdentityKey'] != r['newIdentityKey'] ||
        p['transferNonce'] != expectedTransferNonce)
      throw StateError('Candidate certificate context differs');
    final checked = verifyDeviceKeyTransition(
      payload: p,
      signature: certSignature,
      trustedOldIdentityKey: base64Decode(r['oldIdentityKey'] as String),
      accountId: r['accountId'] as String,
      username: username,
      storedEpoch: p['fromEpoch'] as int,
      nowMs: p['issuedAt'] as int,
    );
    if (checked == null) throw StateError('Candidate proof signature invalid');
    final envelope = {'payload': p, 'signature': certSignature};
    if (r['phase'] != 'staged') {
      if (base64Encode(
            deviceKeyTransitionBytes(
              Map<String, dynamic>.from(
                (r['certificate'] as Map)['payload'] as Map,
              ),
            ),
          ) !=
          base64Encode(deviceKeyTransitionBytes(p)))
        throw StateError('Unresolved candidate proof must not be replaced');
      return _view(r);
    }
    r['certificate'] = envelope;
    r['phase'] = 'verified';
    await _save(r, isOperationCurrent);
    return _view(r);
  });
  Future<PendingTransferCandidate> observeCommit(
    Map<String, dynamic> receipt, {
    required String expectedTransferNonce,
    required bool fromStatus,
    required bool Function() isOperationCurrent,
  }) => _lock.synchronized(() async {
    _current(isOperationCurrent);
    final r = await _load();
    if (r == null || r['phase'] == 'staged')
      throw StateError('Verified candidate proof required');
    final p = (r['certificate'] as Map)['payload'] as Map;
    const allowed = {
      'accountId',
      'epoch',
      'transferNonce',
      'committed',
      'isCurrent',
    };
    if (receipt.keys.any((k) => !allowed.contains(k)) ||
        receipt['accountId'] != r['accountId'] ||
        receipt['epoch'] != p['toEpoch'] ||
        receipt['committed'] != true ||
        p['transferNonce'] != expectedTransferNonce ||
        (!fromStatus && receipt['transferNonce'] != expectedTransferNonce) ||
        (receipt.containsKey('transferNonce') &&
            receipt['transferNonce'] != expectedTransferNonce) ||
        (fromStatus && receipt['isCurrent'] != true) ||
        (receipt.containsKey('isCurrent') && receipt['isCurrent'] != true))
      throw StateError('Commit receipt differs');
    r['receipt'] = {
      'accountId': r['accountId'],
      'epoch': p['toEpoch'],
      'transferNonce': expectedTransferNonce,
      'committed': true,
      'isCurrent': true,
    };
    if (r['phase'] != 'installed') r['phase'] = 'committed';
    await _save(r, isOperationCurrent);
    return _view(r);
  });
  Future<PendingTransferCandidate> installForActivation({
    required String expectedTransferNonce,
    required bool Function() isOperationCurrent,
  }) => _lock.synchronized(() async {
    _current(isOperationCurrent);
    final r = await _load();
    if (r == null ||
        !{'committed', 'installed'}.contains(r['phase']) ||
        (r['receipt'] as Map)['transferNonce'] != expectedTransferNonce)
      throw StateError('Current committed candidate required');
    _current(isOperationCurrent);
    final identity = _identity(r);
    try {
      await _active.installFreshTransferredIdentity(identity);
    } finally {
      identity.dispose();
    }
    _current(isOperationCurrent);
    r['phase'] = 'installed';
    await _save(r, isOperationCurrent);
    return _view(r);
  });
  Future<PendingTransferCandidate> resetAfterUncommittedStatus(
    Map<String, dynamic> receipt, {
    required String expectedTransferNonce,
    required bool Function() isOperationCurrent,
  }) => _lock.synchronized(() async {
    _current(isOperationCurrent);
    final r = await _load();
    if (r == null ||
        r['phase'] != 'verified' ||
        (r['certificate'] as Map)['payload']['transferNonce'] !=
            expectedTransferNonce ||
        receipt.length != 1 ||
        receipt['committed'] != false)
      throw StateError('Fresh uncommitted status required');
    r['phase'] = 'staged';
    r['certificate'] = null;
    r['receipt'] = null;
    await _save(r, isOperationCurrent);
    return _view(r);
  });
}
