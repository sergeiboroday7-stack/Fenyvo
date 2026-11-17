import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/crypto/old_device_pin.dart';

const id = '11111111-1111-4111-8111-111111111111';
void main() {
  OldDevicePin pin() => OldDevicePin.create(
    accountId: id,
    username: 'Alice',
    publicKey: [5, ...List.filled(32, 7)],
  );
  test('public pin round trips with four public fields only', () {
    final p = pin(), copy = OldDevicePin.parse(p.encode());
    expect(copy.accountId, id);
    expect(copy.username, 'Alice');
    expect(copy.publicKey, p.publicKey);
    expect((jsonDecode(p.encode()) as Map).keys.toSet(), {
      'purpose',
      'accountId',
      'username',
      'identityKey',
    });
  });
  test('public key bytes are defensive copies', () {
    final p = pin();
    p.publicKey[1] = 99;
    expect(p.publicKey[1], 7);
  });
  test('rejects malformed account purpose key and extra fields', () {
    final raw = jsonDecode(pin().encode()) as Map;
    for (final entry in <String, dynamic>{
      'accountId': 'bad',
      'purpose': 'other',
      'identityKey': 'bad',
      'extra': true,
    }.entries) {
      expect(
        () => OldDevicePin.parse(jsonEncode({...raw, entry.key: entry.value})),
        throwsFormatException,
      );
    }
  });
  test('rejects noncanonical key whitespace in name and excessive size', () {
    final raw = jsonDecode(pin().encode()) as Map;
    expect(
      () => OldDevicePin.parse(jsonEncode({...raw, 'username': ' Alice'})),
      throwsFormatException,
    );
    expect(() => OldDevicePin.parse(' ' * 2049), throwsFormatException);
    expect(
      () => OldDevicePin.parse(
        jsonEncode({
          ...raw,
          'identityKey': (raw['identityKey'] as String) + '\n',
        }),
      ),
      throwsFormatException,
    );
  });
}
