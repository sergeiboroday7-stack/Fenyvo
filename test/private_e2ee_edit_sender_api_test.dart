import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final socket =
      File('lib/services/socket_service.dart').readAsStringSync();

  test('secure edit sender API exists separately from legacy edit', () {
    expect(socket, contains('bool sendPrivateE2eeEdit({'));
    expect(socket, contains('void editMessage({'));
    expect(socket, contains('E2EE: plaintext private edit blocked'));
  });

  test('secure edit validates original ownership and encryption', () {
    final start = socket.indexOf('bool sendPrivateE2eeEdit({');
    final end = socket.indexOf('void editMessage({', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final sender = socket.substring(start, end);

    expect(sender, contains('originalFrom != owner'));
    expect(sender, contains('originalTo != peer'));
    expect(sender, contains("originalMessage['e2ee'] != true"));
    expect(sender, contains('!isAuthenticated'));
    expect(sender, contains('PrivateE2eeEditProtocol.canApply('));
    expect(sender, contains('Random.secure()'));
  });

  test('secure edit goes to Signal sender, never legacy send', () {
    final start = socket.indexOf('bool sendPrivateE2eeEdit({');
    final end = socket.indexOf('void editMessage({', start);
    final sender = socket.substring(start, end);

    expect(sender, contains('StorageService.saveOutboxMessage('));
    expect(sender, contains('unawaited(_sendE2eeMessage('));
    expect(sender, isNot(contains("_send('edit_message'")));
    expect(sender, isNot(contains("'type': 'outbox_sending'")));
  });

  test('encrypted edit transport and ACK routing remain present', () {
    expect(socket, contains('suppressOrdinaryMessageForAck('));
    expect(socket, contains('needsDedicatedRetry(item)'));
    expect(socket, contains("'type': 'private_e2ee_edit_sent'"));
    expect(socket, contains('unverified private edit event rejected'));
  });
}