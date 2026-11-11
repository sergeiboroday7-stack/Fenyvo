import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy invite rejection never deletes a Signal session', () {
    final source = File('lib/services/socket_service.dart').readAsStringSync();

    expect(
      source.contains(
        'SignalE2eeService.instance.resetPeerSession(peer)',
      ),
      isFalse,
    );

    expect(
      RegExp(
        r'Preserve Signal session and remote identity on legacy invite rejection',
      ).allMatches(source).length,
      2,
    );
  });

  test('fingerprint verification remains conservative after rejection', () {
    final source = File('lib/services/socket_service.dart').readAsStringSync();

    expect(
      RegExp(r'clearFingerprintVerification\(')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(2),
    );
  });
}