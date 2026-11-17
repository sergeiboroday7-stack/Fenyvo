import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:libsignal/libsignal.dart';

const _safe = 9007199254740991;
const _fields = {
  'purpose',
  'accountId',
  'username',
  'oldIdentityHash',
  'newIdentityKey',
  'fromEpoch',
  'toEpoch',
  'issuedAt',
  'transferNonce',
};

Uint8List _key(String value) {
  final key = base64Decode(value);
  if (key.length != 33 || key.first != 5 || base64Encode(key) != value) {
    throw const FormatException('Invalid transition public key');
  }
  return key;
}

bool _hex(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

/// Durable certificate domain, deliberately distinct from short-lived approval.
Uint8List deviceKeyTransitionBytes(Map<String, dynamic> payload) {
  if (payload.length != _fields.length ||
      payload.keys.any((k) => !_fields.contains(k))) {
    throw const FormatException('Invalid transition fields');
  }
  final id = payload['accountId'],
      name = payload['username'],
      key = payload['newIdentityKey'],
      from = payload['fromEpoch'],
      to = payload['toEpoch'],
      issued = payload['issuedAt'];
  if (payload['purpose'] != 'fenyvo-device-key-transition-v1' ||
      id is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id) ||
      name is! String ||
      name.isEmpty ||
      name != name.trim() ||
      utf8.encode(name).length > 128 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
      key is! String ||
      !_hex(payload['oldIdentityHash']) ||
      !_hex(payload['transferNonce']) ||
      from is! int ||
      from < 0 ||
      from >= _safe ||
      to is! int ||
      to != from + 1 ||
      to > _safe ||
      issued is! int ||
      issued < 0 ||
      issued > _safe) {
    throw const FormatException('Invalid transition binding');
  }
  if (sha256.convert(_key(key)).toString() == payload['oldIdentityHash']) {
    throw const FormatException('Transition must change the identity');
  }
  return Uint8List.fromList(
    utf8.encode(
      'FENYVO_DEVICE_KEY_TRANSITION_V1\u0000' +
          jsonEncode([
            payload['purpose'],
            id,
            name,
            payload['oldIdentityHash'],
            key,
            from,
            to,
            issued,
            payload['transferNonce'],
          ]),
    ),
  );
}

bool _context(
  Map<String, dynamic> p, {
  required String accountId,
  required String username,
  required List<int> oldKey,
  required int fromEpoch,
  required int nowMs,
}) =>
    oldKey.length == 33 &&
    oldKey.first == 5 &&
    p['accountId'] == accountId &&
    p['username'] == username &&
    p['oldIdentityHash'] == sha256.convert(oldKey).toString() &&
    p['fromEpoch'] == fromEpoch &&
    nowMs >= 0 &&
    nowMs <= _safe &&
    nowMs >= (p['issuedAt'] as int);

String signDeviceKeyTransition({
  required Map<String, dynamic> payload,
  required IdentityKeyPair identity,
  required String accountId,
  required String username,
  required int fromEpoch,
  required List<int> newIdentityKey,
  required String transferNonce,
  required int nowMs,
  required bool userConfirmed,
}) {
  final copy = Map<String, dynamic>.from(payload);
  final bytes = deviceKeyTransitionBytes(copy);
  if (!userConfirmed ||
      !_context(
        copy,
        accountId: accountId,
        username: username,
        oldKey: identity.publicKey,
        fromEpoch: fromEpoch,
        nowMs: nowMs,
      ) ||
      copy['transferNonce'] != transferNonce ||
      copy['newIdentityKey'] != base64Encode(newIdentityKey)) {
    throw StateError('Unconfirmed or mismatched key transition');
  }
  return base64Encode(identity.sign(message: bytes));
}

class VerifiedDeviceKeyTransition {
  VerifiedDeviceKeyTransition._(this.payload, this.signature);
  final Map<String, dynamic> payload;
  final String signature;
  int get toEpoch => payload['toEpoch'] as int;
  Uint8List get newIdentityKey => _key(payload['newIdentityKey'] as String);
}

/// The old public key and stored epoch must come from existing local trust.
/// There is no expiry: replay protection is the exact prior key AND epoch.
/// This function performs no storage, session, contact or authorization changes.
VerifiedDeviceKeyTransition? verifyDeviceKeyTransition({
  required Map<String, dynamic> payload,
  required String signature,
  required List<int> trustedOldIdentityKey,
  required String accountId,
  required String username,
  required int storedEpoch,
  required int nowMs,
}) {
  PublicKey? key;
  try {
    final copy = Map<String, dynamic>.from(payload),
        bytes = deviceKeyTransitionBytes(copy),
        sig = base64Decode(signature);
    if (sig.length != 64 ||
        base64Encode(sig) != signature ||
        !_context(
          copy,
          accountId: accountId,
          username: username,
          oldKey: trustedOldIdentityKey,
          fromEpoch: storedEpoch,
          nowMs: nowMs,
        ))
      return null;
    key = PublicKey.deserialize(bytes: trustedOldIdentityKey);
    if (!key.verify(message: bytes, signature: sig)) return null;
    return VerifiedDeviceKeyTransition._(
      Map<String, dynamic>.unmodifiable(copy),
      signature,
    );
  } catch (_) {
    return null;
  } finally {
    key?.dispose();
  }
}

class VerifiedDeviceKeyTransitionChain {
  VerifiedDeviceKeyTransitionChain._(List<VerifiedDeviceKeyTransition> items)
    : transitions = List<VerifiedDeviceKeyTransition>.unmodifiable(items);
  final List<VerifiedDeviceKeyTransition> transitions;
  int get finalEpoch => transitions.last.toEpoch;
  Uint8List get finalIdentityKey => transitions.last.newIdentityKey;
}

/// Bounded offline catch-up. Each link is verified by the preceding pinned key.
/// Caller must later persist the key+epoch transactionally; this is verification only.
VerifiedDeviceKeyTransitionChain? verifyDeviceKeyTransitionChain({
  required List<Map<String, dynamic>> certificates,
  required List<int> trustedOldIdentityKey,
  required String accountId,
  required String username,
  required int storedEpoch,
  required int nowMs,
}) {
  if (certificates.isEmpty || certificates.length > 32) return null;
  var key = Uint8List.fromList(trustedOldIdentityKey), epoch = storedEpoch;
  final verified = <VerifiedDeviceKeyTransition>[];
  for (final envelope in certificates) {
    if (envelope.length != 2 ||
        envelope['payload'] is! Map ||
        envelope['signature'] is! String)
      return null;
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    } catch (_) {
      return null;
    }
    final item = verifyDeviceKeyTransition(
      payload: payload,
      signature: envelope['signature'] as String,
      trustedOldIdentityKey: key,
      accountId: accountId,
      username: username,
      storedEpoch: epoch,
      nowMs: nowMs,
    );
    if (item == null) return null;
    verified.add(item);
    key = item.newIdentityKey;
    epoch = item.toEpoch;
  }
  return VerifiedDeviceKeyTransitionChain._(verified);
}
