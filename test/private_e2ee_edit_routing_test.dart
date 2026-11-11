import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal edit is routed separately before ordinary message handling', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final start = source.indexOf("if (type == 'message') {");
    final end = source.indexOf(
      "if (type == 'message_delivered') {",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final section = source.substring(start, end);
    final decrypt = section.indexOf(
      'SignalE2eeService.instance.decrypt(',
    );
    final identity = section.indexOf('E2EE envelope mismatch');
    final kind = section.indexOf(
      "decrypted['kind'] == 'private_edit_v1'",
    );
    final dispatch = section.indexOf("'type': 'private_e2ee_edit'");
    final ordinary = section.indexOf(
      "final text = data['text']",
    );

    expect(decrypt, greaterThanOrEqualTo(0));
    expect(identity, greaterThan(decrypt));
    expect(kind, greaterThan(identity));
    expect(dispatch, greaterThan(kind));
    expect(ordinary, greaterThan(dispatch));

    final editBranch = section.substring(kind, ordinary);
    expect(editBranch, contains('authenticatedFrom'));
    expect(editBranch, contains('return;'));
    expect(editBranch, isNot(contains('showMessageNotification')));
  });
}