import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final socket =
      File('lib/services/socket_service.dart').readAsStringSync();
  final chat =
      File('lib/screens/chat_screen.dart').readAsStringSync();

  test('receiver persists Signal edit without an open chat', () {
    final start = socket.indexOf("if (decrypted['kind'] == 'private_edit_v1')");
    final end = socket.indexOf("} catch (error) {", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final route = socket.substring(start, end);

    final persist = route.indexOf(
      'saved = await StorageService.mutateMessagesDurably(',
    );
    final notify = route.indexOf(
      "'type': 'private_e2ee_edit'",
    );

    expect(persist, greaterThanOrEqualTo(0));
    expect(notify, greaterThan(persist));
    expect(route, contains('PrivateE2eeEditProtocol.canApply('));
    expect(route, contains('SocketEventGenerationGuard.isCurrent('));
    expect(route, contains("item['lastEditEventId'] = editId"));
    expect(route, contains('StorageService.getMessagesVisibleForOwner('));
  });

  test('open chat refreshes an already persisted edit', () {
    final start = chat.indexOf("if (type == 'private_e2ee_edit') {");
    final end = chat.indexOf("if (type == 'message_edited') {", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final route = chat.substring(start, end);

    expect(route, contains('StorageService.getMessagesVisibleForOwner('));
    expect(route, contains('_loadMessages();'));
    expect(route, contains("if (!saved || !mounted ||"));
  });

  test('protected edit still uses encryption only', () {
    expect(socket, contains('SignalE2eeService.instance.encrypt('));
    expect(socket, contains("if (!_send('e2ee_message', envelope))"));
    expect(socket, contains('E2EE: plaintext private edit blocked'));
  });
}