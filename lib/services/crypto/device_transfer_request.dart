import 'dart:convert';
import 'dart:typed_data';

import 'device_transfer_approval.dart';

/// Immutable, short-lived request. Parsing never grants trust or signs anything.
class DeviceTransferRequest {
  DeviceTransferRequest._(this.data, {this.fromEpoch});
  final int? fromEpoch;
  final Map<String, dynamic> data;
  String get nonce => data['nonce'] as String;
  String get candidateHash => data['candidateHash'] as String;
  String get accountId => data['accountId'] as String;
  String get username => data['username'] as String;
  int get expiresAt => data['expiresAt'] as int;
  Uint8List get newIdentityKey =>
      base64Decode(data['newIdentityKey'] as String);
  bool validAt(int nowMs) =>
      nowMs >= (data['issuedAt'] as int) && nowMs < expiresAt;

  static DeviceTransferRequest? parseV2(
    Map<String, dynamic> source, {
    required String accountId,
    required String username,
    required int nowMs,
  }) {
    final epoch = source['fromEpoch'];
    if (source.length != 9 ||
        epoch is! int ||
        epoch < 0 ||
        epoch >= 9007199254740991)
      return null;
    final copy = Map<String, dynamic>.from(source)..remove('fromEpoch');
    final request = parse(
      copy,
      accountId: accountId,
      username: username,
      nowMs: nowMs,
    );
    return request == null
        ? null
        : DeviceTransferRequest._(request.data, fromEpoch: epoch);
  }

  static DeviceTransferRequest? parse(
    Map<String, dynamic> source, {
    required String accountId,
    required String username,
    required int nowMs,
  }) {
    try {
      const fields = {
        'purpose',
        'accountId',
        'username',
        'newIdentityKey',
        'candidateHash',
        'nonce',
        'issuedAt',
        'expiresAt',
      };
      if (source.length != fields.length ||
          source.keys.any((k) => !fields.contains(k)))
        return null;
      final copy = Map<String, dynamic>.from(source);
      deviceTransferApprovalBytes({...copy, 'oldIdentityHash': '0' * 64});
      final request = DeviceTransferRequest._(
        Map<String, dynamic>.unmodifiable(copy),
      );
      if (request.accountId != accountId ||
          request.username != username ||
          !request.validAt(nowMs))
        return null;
      return request;
    } catch (_) {
      return null;
    }
  }
}
