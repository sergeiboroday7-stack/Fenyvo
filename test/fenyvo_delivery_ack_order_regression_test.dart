import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readSource(String relativePath) {
    return File(relativePath).readAsStringSync();
  }

  test('incoming socket handler does not ACK before persistence', () {
    final source = readSource('lib/services/socket_service.dart');
    final start = source.indexOf("if (type == 'message') {");
    final end = source.indexOf(
      "if (type == 'message_delivered') {",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final incomingHandler = source.substring(start, end);

    expect(
      incomingHandler.contains('sendMessageDelivered('),
      isFalse,
    );
    expect(
      incomingHandler.contains(
        'SignalE2eeService.instance.decrypt(',
      ),
      isTrue,
    );
  });

  test('recipient ACK follows durable write and saved-record check', () {
    final source = readSource('lib/screens/chat_list_screen.dart');
    final start = source.indexOf("if (type == 'message') {");
    final end = source.indexOf("if (type == 'message_sent') {", start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);

    final save = handler.indexOf(
      'final appended = await StorageService.appendMessageDurably(',
    );
    final blockedCheck = handler.indexOf(
      'final blockedAfterAppend = await FenyvoTrustService.isBlocked(',
    );
    final savedRecordCheck = handler.indexOf('final persistedForAck');
    final ackCondition = handler.indexOf('if (persistedForAck) {');
    final ack = handler.indexOf(
      'SocketService.instance.sendMessageDelivered(',
    );

    expect(save, greaterThanOrEqualTo(0));
    expect(blockedCheck, greaterThan(save));
    expect(savedRecordCheck, greaterThan(blockedCheck));
    expect(ackCondition, greaterThan(savedRecordCheck));
    expect(ack, greaterThan(ackCondition));

    expect(
      handler.contains("stored['e2ee'] == true"),
      isTrue,
    );
    expect(
      handler.contains('!blockedAfterAppend'),
      isTrue,
    );
    expect(
      handler.contains('!hiddenForOwner'),
      isTrue,
    );
    expect(
      handler.contains(
        'SocketService.instance.currentUser?.trim() == currentUser',
      ),
      isTrue,
    );
  });
}