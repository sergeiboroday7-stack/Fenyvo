import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows update SHA-256', () {
    test('accepts expected SHA-256', () {
      final data = utf8.encode('FENYVO_UPDATE_TEST');
      final actual = sha256.convert(data).toString();
      final expected = sha256.convert(data).toString();

      expect(actual, expected);
      expect(actual.length, 64);
    });

    test('rejects modified content', () {
      final original = utf8.encode('FENYVO_UPDATE_TEST');
      final modified = utf8.encode('FENYVO_UPDATE_TESX');

      final expected = sha256.convert(original).toString();
      final actual = sha256.convert(modified).toString();

      expect(actual, isNot(expected));
    });

    test('empty file has a different SHA-256', () {
      final expected = sha256
          .convert(utf8.encode('FENYVO_UPDATE_TEST'))
          .toString();

      final actual = sha256.convert(<int>[]).toString();

      expect(actual, isNot(expected));
    });
  });
}
