import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('post-decrypt PreKey maintenance catches asynchronous failure', () {
    final source = File('lib/services/crypto/signal_e2ee_service.dart')
        .readAsStringSync();
    expect(source, contains('unawaited(_ensurePreKeys().catchError('));
    expect(source, contains('Background PreKey refill failed'));
    // Initialisation and bundle publication must still await failures.
    expect(RegExp(r'await _ensurePreKeys\(\);').allMatches(source).length, 2);
    expect(source, isNot(contains('unawaited(_ensurePreKeys());')));
  });
}
