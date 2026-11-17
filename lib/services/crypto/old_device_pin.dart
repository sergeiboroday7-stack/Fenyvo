import 'dart:convert';
import 'dart:typed_data';

import 'device_transfer_approval.dart';

import 'package:crypto/crypto.dart';

/// Public data received directly from the old device, never from the relay.
class OldDevicePin {
  OldDevicePin._(this.accountId, this.username, this.identityKey);
  final String accountId, username, identityKey;
  Uint8List get publicKey => base64Decode(identityKey);
  static OldDevicePin create({
    required String accountId,
    required String username,
    required List<int> publicKey,
  }) => parse(
    jsonEncode({
      'purpose': 'fenyvo-transfer-old-device-pin-v1',
      'accountId': accountId,
      'username': username,
      'identityKey': base64Encode(publicKey),
    }),
  );
  static OldDevicePin parse(String token) {
    if (token.length > 2048) throw const FormatException('Pin too long');
    final raw = jsonDecode(token);
    if (raw is! Map ||
        raw.length != 4 ||
        raw['purpose'] != 'fenyvo-transfer-old-device-pin-v1' ||
        raw.keys.any(
          (k) =>
              !{'purpose', 'accountId', 'username', 'identityKey'}.contains(k),
        ) ||
        raw['accountId'] is! String ||
        raw['username'] is! String ||
        raw['identityKey'] is! String) {
      throw const FormatException('Invalid old device pin');
    }
    final key = base64Decode(raw['identityKey'] as String);
    // Reuse the strict protocol account/name/key encoding checks, with a synthetic target.
    final candidate = key;
    deviceTransferApprovalBytes({
      'purpose': 'fenyvo-device-transfer-v1',
      'accountId': raw['accountId'],
      'username': raw['username'],
      'oldIdentityHash': '0' * 64,
      'newIdentityKey': base64Encode(candidate),
      'candidateHash': sha256.convert(candidate).toString(),
      'nonce': '0' * 64,
      'issuedAt': 0,
      'expiresAt': 1,
    });
    if (key.length != 33 ||
        key.first != 5 ||
        base64Encode(key) != raw['identityKey'])
      throw const FormatException('Invalid old public key');
    return OldDevicePin._(
      raw['accountId'] as String,
      raw['username'] as String,
      raw['identityKey'] as String,
    );
  }

  String encode() => jsonEncode({
    'purpose': 'fenyvo-transfer-old-device-pin-v1',
    'accountId': accountId,
    'username': username,
    'identityKey': identityKey,
  });
}
