import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final socket = File('lib/services/socket_service.dart').readAsStringSync();
  final chat = File('lib/screens/chat_screen.dart').readAsStringSync();

  test('edit ACK persists before removing outbox entry', () {
    final start = socket.indexOf("if (type == 'message_sent') {");
    final end = socket.indexOf('if (const <String>{', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = socket.substring(start, end);

    final persist =
        section.indexOf('saved = await StorageService.mutateMessagesDurably(');
    final remove = section.indexOf(
        'StorageService.removeOutboxMessage(user, id)', persist);

    expect(persist, greaterThanOrEqualTo(0));
    expect(remove, greaterThan(persist));
    expect(section, contains('if (!saved) {'));
    expect(section, contains("item['lastEditEventId'] = id"));
  });

  test('unmatched edit ACK cannot fall through as new message', () {
    final start = socket.indexOf("if (type == 'message_sent') {");
    final end = socket.indexOf('if (const <String>{', start);
    final section = socket.substring(start, end);

    expect(section, contains('editPolicy.isEditOperation(pending)'));
    expect(section, contains('if (!validAck ||'));
    expect(section, contains("'type': 'private_e2ee_edit_sent'"));
    expect(section, contains("'type': 'outbox_sent'"));
  });

  test('screen reloads durable edit when already saved', () {
    final start = chat.indexOf("if (type == 'private_e2ee_edit_sent')");
    final end = chat.indexOf("if (type == 'private_e2ee_edit')", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final section = chat.substring(start, end);

    expect(section, contains('if (!saved ||'));
    expect(section, contains('StorageService.getMessagesVisibleForOwner('));
    expect(section, contains("item['lastEditEventId']"));
    expect(section, contains('_loadMessages();'));
  });
}