import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;
  setUpAll(() {
    source = File('lib/services/socket_service.dart').readAsStringSync();
  });

  test('Signal sender encrypts dedicated edit payload on both paths', () {
    final start = source.indexOf('Future<void> _sendE2eeMessage(');
    final end = source.indexOf('Map<String, dynamic> _privateE2eePayload(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final sender = source.substring(start, end);
    expect(sender, contains('isValidEditOperation(localMessage)'));
    expect(sender, contains("'targetMessageId': localMessage['targetMessageId']"));
    expect(sender, contains("'newText': localMessage['newText']"));
    expect(
      RegExp(r'SignalE2eeService.instance.encrypt\(\s*target,\s*securePayload,')
          .allMatches(sender).length,
      2,
    );
  });

  test('edit ACK exits before ordinary outbox event', () {
    final start = source.indexOf("if (type == 'message_sent') {");
    final end = source.indexOf('if (const <String>{', start);
    final ack = source.substring(start, end);
    expect(ack, contains('suppressOrdinaryMessageForAck('));
    expect(ack, contains("'type': 'private_e2ee_edit_sent'"));
    final edit = ack.indexOf('suppressOrdinaryMessageForAck(');
    final ordinary = ack.indexOf("'type': 'outbox_sent'");
    expect(ordinary, greaterThan(edit));
    expect(ack.substring(edit, ordinary), contains('return;'));
  });

  test('retry distinguishes edits from normal messages', () {
    final start = source.indexOf('Future<void> _flushOutbox()');
    final end = source.indexOf('Future<void> _sendE2eeMessage(', start);
    final retry = source.substring(start, end);
    expect(retry, contains('needsDedicatedRetry(item)'));
    expect(retry, contains('isValidEditOperation(item)'));
    expect(retry, contains('_sendE2eeMessage('));
  });

  test('plaintext edit and forged inbound event remain blocked', () {
    expect(source, contains('E2EE: plaintext private edit blocked'));
    expect(source, contains("if (type == 'private_e2ee_edit')"));
  });
}