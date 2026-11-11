import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String chat;
  late String socket;

  setUpAll(() {
    chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    socket = File('lib/services/socket_service.dart').readAsStringSync();
  });

  test('edit UI uses only the protected Signal API', () {
    final start = chat.indexOf(
      'Future<void> _editMessage(Map<String, dynamic> message) async {',
    );
    final end = chat.indexOf(
      'Future<void> _deleteMessageForMe(',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final section = chat.substring(start, end);
    expect(section, contains('sendPrivateE2eeEdit('));
    expect(
      section,
      contains('originalMessage: Map<String, dynamic>.from(message)'),
    );
    expect(section, contains("message['e2ee'] != true"));
    expect(section, isNot(contains('SocketService.instance.editMessage(')));
  });

  test('failed edit submission shows localized feedback', () {
    final start = chat.indexOf(
      'Future<void> _editMessage(Map<String, dynamic> message) async {',
    );
    final end = chat.indexOf(
      'Future<void> _deleteMessageForMe(',
      start,
    );
    final section = chat.substring(start, end);

    expect(section, contains('if (!accepted && mounted)'));
    expect(section, contains('Не удалось отправить'));
    expect(section, contains('Не вдалося надіслати'));
    expect(section, contains('Could not send encrypted edit'));
  });

  test('Signal sender and plaintext guard remain intact', () {
    expect(socket, contains('bool sendPrivateE2eeEdit({'));
    expect(socket, contains('PrivateE2eeEditProtocol.canApply('));
    expect(socket, contains('Random.secure()'));
    expect(socket, contains('E2EE: plaintext private edit blocked'));
  });

  test('separate ACK and retry routing remain intact', () {
    expect(socket, contains("'type': 'private_e2ee_edit_sent'"));
    expect(socket, contains('needsDedicatedRetry(item)'));
    expect(socket, contains('suppressOrdinaryMessageForAck('));
  });
}