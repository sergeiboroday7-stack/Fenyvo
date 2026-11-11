import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String chat;
  late String socket;

  setUpAll(() {
    chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    socket = File('lib/services/socket_service.dart').readAsStringSync();
  });

  test('local ACK handled before verified remote edit', () {
    final ack = chat.indexOf(
      "if (type == 'private_e2ee_edit_sent')",
    );
    final remote = chat.indexOf(
      "if (type == 'private_e2ee_edit')",
    );

    expect(ack, greaterThanOrEqualTo(0));
    expect(remote, greaterThan(ack));
  });

  test('local ACK validates owner target and original message', () {
    final start = chat.indexOf(
      "if (type == 'private_e2ee_edit_sent')",
    );
    final end = chat.indexOf(
      "if (type == 'private_e2ee_edit')",
      start,
    );
    final section = chat.substring(start, end);

    expect(section, contains("data['operation']"));
    expect(section, contains("data['id']"));
    expect(section, contains("operation['from']"));
    expect(section, contains("operation['to']"));
    expect(section, contains('PrivateE2eeEditProtocol.canApply('));
    expect(section, contains('authenticatedFrom: owner'));
    expect(section, contains('StorageService.mutateMessagesDurably('));
  });

  test('local ACK updates existing bubble and reply previews', () {
    final start = chat.indexOf(
      "if (type == 'private_e2ee_edit_sent')",
    );
    final end = chat.indexOf(
      "if (type == 'private_e2ee_edit')",
      start,
    );
    final section = chat.substring(start, end);

    expect(section, contains("item['text'] = operation['newText']"));
    expect(section, contains("item['isEdited'] = true"));
    expect(section, contains("item['lastEditEventId'] = eventId"));
    expect(section, contains("item['replyTo'] = {"));
    expect(section, contains('if (!saved ||'));
    expect(section, isNot(contains('_addMessageIfNotExists(')));
  });

  test('network cannot inject internal edit ACK', () {
    expect(
      socket,
      contains("if (type == 'private_e2ee_edit_sent')"),
    );
    expect(
      socket,
      contains('unverified private edit ACK rejected'),
    );
  });
}