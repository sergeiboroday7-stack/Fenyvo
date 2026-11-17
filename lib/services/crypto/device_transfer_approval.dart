import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:libsignal/libsignal.dart';

const _fields = <String>{
  'purpose',
  'accountId',
  'username',
  'oldIdentityHash',
  'newIdentityKey',
  'candidateHash',
  'nonce',
  'issuedAt',
  'expiresAt',
};
const _safeInteger = 9007199254740991;
bool _hex(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
String _text(Map<String, dynamic> p, String name) {
  final value = p[name];
  if (value is! String) throw const FormatException('Invalid transfer field');
  return value;
}

Uint8List _decode(String value, int size) {
  final bytes = base64Decode(value);
  if (bytes.length != size || base64Encode(bytes) != value)
    throw const FormatException('Noncanonical transfer encoding');
  return bytes;
}

Uint8List deviceTransferApprovalBytes(Map<String, dynamic> p) {
  if (p.length != _fields.length || p.keys.any((k) => !_fields.contains(k)))
    throw const FormatException('Unexpected transfer fields');
  final purpose = _text(p, 'purpose'),
      id = _text(p, 'accountId'),
      name = _text(p, 'username'),
      oldHash = _text(p, 'oldIdentityHash'),
      key = _text(p, 'newIdentityKey'),
      candidate = _text(p, 'candidateHash'),
      nonce = _text(p, 'nonce');
  final issued = p['issuedAt'], expires = p['expiresAt'];
  if (purpose != 'fenyvo-device-transfer-v1' ||
      id.length != 36 ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id) ||
      name.isEmpty ||
      name != name.trim() ||
      utf8.encode(name).length > 128 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
      !_hex(oldHash) ||
      !_hex(candidate) ||
      !_hex(nonce))
    throw const FormatException('Invalid transfer binding');
  if (issued is! int ||
      expires is! int ||
      issued < 0 ||
      expires > _safeInteger ||
      expires <= issued ||
      expires - issued > 300000)
    throw const FormatException('Invalid transfer lifetime');
  final bytes = _decode(key, 33);
  if (bytes.first != 5 || sha256.convert(bytes).toString() != candidate)
    throw const FormatException('Invalid candidate identity');
  return Uint8List.fromList(
    utf8.encode(
      'FENYVO_DEVICE_TRANSFER_APPROVAL_V1\u0000' +
          jsonEncode([
            purpose,
            id,
            name,
            oldHash,
            key,
            candidate,
            nonce,
            issued,
            expires,
          ]),
    ),
  );
}

bool _matches(
  Map<String, dynamic> p,
  List<int> oldKey,
  List<int> newKey,
  String accountId,
  String username,
  String nonce,
  int nowMs,
) {
  return oldKey.length == 33 &&
      oldKey.first == 5 &&
      newKey.length == 33 &&
      newKey.first == 5 &&
      p['accountId'] == accountId &&
      p['username'] == username &&
      p['nonce'] == nonce &&
      p['oldIdentityHash'] == sha256.convert(oldKey).toString() &&
      p['newIdentityKey'] == base64Encode(newKey) &&
      p['candidateHash'] == sha256.convert(newKey).toString() &&
      nowMs >= 0 &&
      nowMs <= _safeInteger &&
      nowMs >= (p['issuedAt'] as int) &&
      nowMs < (p['expiresAt'] as int);
}

String signDeviceTransferApproval({
  required Map<String, dynamic> payload,
  required IdentityKeyPair identity,
  required String accountId,
  required String username,
  required List<int> newIdentityKey,
  required String nonce,
  required int nowMs,
}) {
  final p = Map<String, dynamic>.from(payload),
      message = deviceTransferApprovalBytes(p);
  if (!_matches(
    p,
    identity.publicKey,
    newIdentityKey,
    accountId,
    username,
    nonce,
    nowMs,
  ))
    throw StateError('Transfer context mismatch');
  return base64Encode(identity.sign(message: message));
}

bool verifyDeviceTransferApproval({
  required Map<String, dynamic> payload,
  required String signature,
  required List<int> trustedOldIdentityKey,
  required String accountId,
  required String username,
  required List<int> newIdentityKey,
  required String nonce,
  required int nowMs,
}) {
  PublicKey? key;
  try {
    final p = Map<String, dynamic>.from(payload),
        message = deviceTransferApprovalBytes(p);
    if (!_matches(
      p,
      trustedOldIdentityKey,
      newIdentityKey,
      accountId,
      username,
      nonce,
      nowMs,
    ))
      return false;
    final sig = _decode(signature, 64);
    key = PublicKey.deserialize(bytes: trustedOldIdentityKey);
    return key.verify(message: message, signature: sig);
  } catch (_) {
    return false;
  } finally {
    key?.dispose();
  }
}
