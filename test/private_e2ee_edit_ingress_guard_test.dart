import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raw private edit cannot reach general event dispatch', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final general = source.lastIndexOf(
      '_notifyHandlers(message);',
    );

    expect(general, greaterThanOrEqualTo(0));

    final prefix = source.substring(0, general);
    final guard = prefix.lastIndexOf(
      "if (type == 'private_e2ee_edit')",
    );

    expect(guard, greaterThanOrEqualTo(0));

    final guardedSection = source.substring(guard, general);

    expect(guardedSection, contains('return;'));
    expect(
      guardedSection,
      contains('unverified private edit event rejected'),
    );
  });

  test('verified Signal edit retains separate dispatch', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final decrypt = source.indexOf(
      'SignalE2eeService.instance.decrypt(',
    );

    final verified = source.indexOf(
      "if (decrypted['kind'] == 'private_edit_v1')",
    );

    final dispatch = source.indexOf(
      "'type': 'private_e2ee_edit'",
      verified,
    );

    expect(decrypt, greaterThanOrEqualTo(0));
    expect(verified, greaterThan(decrypt));
    expect(dispatch, greaterThan(verified));
  });
}