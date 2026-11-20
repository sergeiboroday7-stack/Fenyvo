import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'device_transfer_approval.dart';

class VerifiedDeviceTransferApproval {
  VerifiedDeviceTransferApproval._(this.payload, this.signature);
  final Map<String, dynamic> payload;
  final String signature;
}

class _PendingApproval {
  _PendingApproval(this.payload, this.oldKey, this.newKey, this.generation);
  final Map<String, dynamic> payload;
  final Uint8List oldKey;
  final Uint8List newKey;
  final int generation;
  int failures = 0;
}

class DeviceTransferApprovalGate {
  _PendingApproval? _pending;
  void clear() {
    _pending = null;
  }

  void begin({
    required Map<String, dynamic> challenge,
    required bool isAuthenticated,
    required String accountId,
    required String username,
    required List<int> trustedOldIdentityKey,
    required List<int> newIdentityKey,
    required int connectionGeneration,
    required int nowMs,
  }) {
    clear();
    const fields = <String>{
      'purpose',
      'accountId',
      'candidateHash',
      'nonce',
      'issuedAt',
      'expiresAt',
    };
    if (!isAuthenticated ||
        connectionGeneration < 0 ||
        challenge.length != fields.length ||
        challenge.keys.any((k) => !fields.contains(k)) ||
        challenge['accountId'] != accountId ||
        trustedOldIdentityKey.length != 33 ||
        trustedOldIdentityKey.first != 5 ||
        newIdentityKey.length != 33 ||
        newIdentityKey.first != 5)
      throw StateError('Invalid pending transfer context');
    final oldKey = Uint8List.fromList(trustedOldIdentityKey),
        newKey = Uint8List.fromList(newIdentityKey);
    final payload = <String, dynamic>{
      ...challenge,
      'username': username,
      'oldIdentityHash': sha256.convert(oldKey).toString(),
      'newIdentityKey': base64Encode(newKey),
    };
    deviceTransferApprovalBytes(payload);
    if (payload['candidateHash'] != sha256.convert(newKey).toString() ||
        nowMs < (payload['issuedAt'] as int) ||
        nowMs >= (payload['expiresAt'] as int))
      throw StateError('Invalid pending transfer timing or target');
    _pending = _PendingApproval(
      Map<String, dynamic>.unmodifiable(payload),
      oldKey,
      newKey,
      connectionGeneration,
    );
  }

  VerifiedDeviceTransferApproval? accept({
    required Map<String, dynamic> payload,
    required String signature,
    required bool isAuthenticated,
    required String currentAccountId,
    required String currentUsername,
    required int connectionGeneration,
    required int nowMs,
  }) {
    final pending = _pending;
    if (pending == null) return null;
    final expected = pending.payload;
    if (!isAuthenticated ||
        currentAccountId != expected['accountId'] ||
        currentUsername != expected['username'] ||
        connectionGeneration != pending.generation ||
        nowMs < (expected['issuedAt'] as int) ||
        nowMs >= (expected['expiresAt'] as int)) {
      clear();
      return null;
    }
    var valid = false;
    Map<String, dynamic>? copy;
    try {
      copy = Map<String, dynamic>.from(payload);
      valid =
          copy['issuedAt'] == expected['issuedAt'] &&
          copy['expiresAt'] == expected['expiresAt'] &&
          verifyDeviceTransferApproval(
            payload: copy,
            signature: signature,
            trustedOldIdentityKey: pending.oldKey,
            accountId: currentAccountId,
            username: currentUsername,
            newIdentityKey: pending.newKey,
            nonce: expected['nonce'] as String,
            nowMs: nowMs,
          );
    } catch (_) {
      valid = false;
    }
    if (!valid) {
      pending.failures++;
      if (pending.failures >= 3) clear();
      return null;
    }
    clear();
    return VerifiedDeviceTransferApproval._(
      Map<String, dynamic>.unmodifiable(copy!),
      signature,
    );
  }
}
