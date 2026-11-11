import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final socket =
      File('lib/services/socket_service.dart').readAsStringSync();

  test('ACK rechecks account and connection around durable write', () {
    final start = socket.indexOf("if (type == 'message_sent') {");
    final end = socket.indexOf('if (const <String>{', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final ack = socket.substring(start, end);

    final write = ack.indexOf(
      'saved = await StorageService.mutateMessagesDurably(',
    );
    final first = ack.indexOf('SocketEventGenerationGuard.isCurrent(');
    final second = ack.indexOf(
      'SocketEventGenerationGuard.isCurrent(',
      write,
    );
    final removal = ack.indexOf(
      'StorageService.removeOutboxMessage(user, id)',
    );

    expect(first, greaterThanOrEqualTo(0));
    expect(write, greaterThan(first));
    expect(second, greaterThan(write));
    expect(removal, greaterThan(second));
  });

  test('duplicate ACK checks already persisted event ID', () {
    final start = socket.indexOf("if (type == 'message_sent') {");
    final end = socket.indexOf('if (const <String>{', start);
    final ack = socket.substring(start, end);

    expect(ack, contains('if (!saved) {'));
    expect(ack, contains(
      'saved = StorageService.getMessagesVisibleForOwner(',
    ));
    expect(ack, contains("item['lastEditEventId']"));
    expect(ack, contains("item['e2ee'] == true"));
    expect(ack, contains("item['from']?.toString().trim() == user"));
    expect(ack, contains("item['to']?.toString().trim() == peer"));
  });

  test('legacy plaintext edits remain blocked', () {
    expect(socket, contains('E2EE: plaintext private edit blocked'));
    expect(socket, contains('unverified private edit ACK rejected'));
    expect(socket, contains('unverified private edit event rejected'));
  });
}