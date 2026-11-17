import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/crypto/device_transfer_request.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> source() {
  final key = [5, ...List<int>.filled(32, 9)];
  return {
    'purpose': 'fenyvo-device-transfer-v1',
    'accountId': id,
    'username': 'Alice',
    'newIdentityKey': base64Encode(key),
    'candidateHash': sha256.convert(key).toString(),
    'nonce': 'b' * 64,
    'issuedAt': 1000,
    'expiresAt': 121000,
  };
}

DeviceTransferRequest? parse(
  Map<String, dynamic> p, {
  int now = 1001,
  String owner = 'Alice',
}) =>
    DeviceTransferRequest.parse(p, accountId: id, username: owner, nowMs: now);
void main() {
  test('accepts strictly bound current request', () {
    expect(parse(source()), isNotNull);
  });
  test('rejects another account or username', () {
    expect(
      parse({...source(), 'accountId': '22222222-2222-4222-8222-222222222222'}),
      isNull,
    );
    expect(parse(source(), owner: 'Bob'), isNull);
  });
  test('rejects expiry and future issuance', () {
    expect(parse(source(), now: 121000), isNull);
    expect(parse(source(), now: 999), isNull);
  });
  test('rejects substituted key hash and extra fields', () {
    expect(parse({...source(), 'candidateHash': 'a' * 64}), isNull);
    expect(parse({...source(), 'extra': true}), isNull);
  });
  test('request and key access are defensive copies', () {
    final p = source(), r = parse(p)!;
    p['username'] = 'Bob';
    r.newIdentityKey[1] = 0;
    expect(r.username, 'Alice');
    expect(r.newIdentityKey[1], 9);
    expect(() => r.data['username'] = 'Bob', throwsUnsupportedError);
  });
  test('rejects malformed times encodings nonce and purpose', () {
    for (final entry in <String, dynamic>{
      'issuedAt': 1.5,
      'expiresAt': 999999,
      'newIdentityKey': 'bad',
      'nonce': 'x',
      'purpose': 'other',
    }.entries) {
      expect(parse({...source(), entry.key: entry.value}), isNull);
    }
  });
}
