import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('lib/services/socket_service.dart').readAsStringSync();

  test('edit ACK carries its local operation before outbox removal', () {
    final start = source.indexOf("if (type == 'message_sent') {");
    final end = source.indexOf('if (const <String>{', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final section = source.substring(start, end);

    expect(section, contains('suppressOrdinaryMessageForAck('));
    expect(section, contains(
      "'operation': Map<String, dynamic>.from(pending)",
    ));
    expect(section, contains("'type': 'private_e2ee_edit_sent'"));
    expect(section, contains('StorageService.removeOutboxMessage(user, id)'));

    final editAck = section.indexOf("'type': 'private_e2ee_edit_sent'");
    final ordinaryAck = section.indexOf("'type': 'outbox_sent'");

    expect(editAck, greaterThanOrEqualTo(0));
    expect(ordinaryAck, greaterThan(editAck));
    expect(section.substring(editAck, ordinaryAck), contains('return;'));
  });

  test('external forged internal ACK is rejected', () {
    final guard = source.indexOf(
      "if (type == 'private_e2ee_edit_sent')",
    );

    final normalDispatch = source.indexOf(
      '_notifyHandlers(message);',
      guard,
    );

    expect(guard, greaterThanOrEqualTo(0));
    expect(normalDispatch, greaterThan(guard));

    final section = source.substring(guard, normalDispatch);
    expect(section, contains('return;'));
    expect(section, contains('unverified private edit ACK rejected'));
  });

  test('Signal edit and legacy plaintext protections remain', () {
    expect(source, contains('SignalE2eeService.instance.encrypt('));
    expect(source, contains('needsDedicatedRetry(item)'));
    expect(source, contains('E2EE: plaintext private edit blocked'));
  });
}