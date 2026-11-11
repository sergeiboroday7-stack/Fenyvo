import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('lib/services/socket_service.dart').readAsStringSync();

  test('delivery cleanup is scoped to authenticated connection', () {
    final start = source.indexOf(
      "if (type == 'message_delivered')",
    );
    final end = source.indexOf(
      "if (type == 'message_read')",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);

    expect(handler, contains('SocketEventGenerationGuard.isCurrent'));
    expect(handler, contains('isAuthenticated'));
    expect(handler, contains('ackFrom == owner'));
    expect(handler, contains('ackTo != owner'));
    expect(handler, contains('matching.length == 1'));
    expect(handler, contains(
      'StorageService.removeOutboxMessage(owner, messageId)',
    ));
  });

  test('cleanup requires exact encrypted outbox ownership', () {
    final start = source.indexOf(
      "if (type == 'message_delivered')",
    );
    final end = source.indexOf(
      "if (type == 'message_read')",
      start,
    );
    final handler = source.substring(start, end);

    expect(handler, contains("item['id']?.toString().trim() == messageId"));
    expect(handler, contains("item['from']?.toString().trim() == owner"));
    expect(handler, contains("item['to']?.toString().trim() == ackTo"));
    expect(handler, contains("item['e2ee'] == true"));
    expect(handler, contains("'server_accepted'"));
    expect(handler, contains("'decrypt_failed'"));

    expect(handler, isNot(contains('resetPeerSession(')));
    expect(handler, isNot(contains('deleteSession(')));
    expect(handler, isNot(contains('_sendE2eeMessage(')));
  });

  test('server acceptance alone still retains E2EE outbox', () {
    final start = source.indexOf(
      "if (type == 'message_sent')",
    );
    final end = source.indexOf(
      "if (const <String>{",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(
      handler,
      contains(
        "StorageService.updateOutboxStatus(user, id, 'server_accepted')",
      ),
    );
  });
}