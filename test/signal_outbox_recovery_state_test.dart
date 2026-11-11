import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/services/socket_service.dart').readAsStringSync();

  test('server ACK preserves E2EE outbox for recovery', () {
    final start = source.indexOf("if (type == 'message_sent')");
    final end = source.indexOf("if (const <String>{", start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(handler, contains("data['e2ee'] == true"));
    expect(
      handler,
      contains("updateOutboxStatus(user, id, 'server_accepted')"),
    );
    expect(handler, contains('StorageService.removeOutboxMessage(user, id)'));
  });

  test('outbox flush never automatically retries accepted or failed E2EE', () {
    final start = source.indexOf('Future<void> _flushOutbox()');
    final end = source.indexOf('// РЕГИСТРАЦИЯ', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final flush = source.substring(start, end);
    final accepted = flush.indexOf("recoveryStatus == 'server_accepted'");
    final failed = flush.indexOf("recoveryStatus == 'decrypt_failed'");
    final send = flush.indexOf('_sendE2eeMessage(');

    expect(accepted, greaterThanOrEqualTo(0));
    expect(failed, greaterThan(accepted));
    expect(send, greaterThan(failed));
    expect(flush, contains('continue;'));
  });

  test('failure notification requires owned original E2EE message', () {
    final start = source.indexOf(
      "if (type == 'e2ee_decrypt_failure')",
    );
    final end = source.indexOf(
      "if (type == 'e2ee_prekey_bundle')", start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(handler, contains("item['id']?.toString().trim() == messageId"));
    expect(handler, contains("item['from']?.toString().trim() == owner"));
    expect(handler, contains("item['to']?.toString().trim() == peer"));
    expect(handler, contains("item['e2ee'] == true"));
    expect(handler, contains("item['status']?.toString() == 'server_accepted'"));
    expect(handler, contains("originalMessage.length != 1"));
    expect(handler, contains(
      "updateOutboxStatus(owner, messageId, 'decrypt_failed')",
    ));
    expect(handler, isNot(contains('resetPeerSession(')));
    expect(handler, isNot(contains('_sendE2eeMessage(')));
  });
}