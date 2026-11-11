import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/private_e2ee_edit_protocol.dart';

void main() {
  test('private Signal edit has a dedicated durable consumer', () {
    final source =
        File('lib/screens/chat_screen.dart').readAsStringSync();

    final secure = source.indexOf(
      "if (type == 'private_e2ee_edit') {",
    );
    final legacy = source.indexOf(
      "if (type == 'message_edited') {",
    );

    expect(secure, greaterThanOrEqualTo(0));
    expect(legacy, greaterThan(secure));

    final section = source.substring(secure, legacy);

    expect(section, contains('PrivateE2eeEditProtocol.canApply('));
    expect(section, contains('mutateMessagesDurably('));
    expect(section, contains('lastEditEventId'));
    expect(section, contains('authenticatedFrom'));
    expect(section, contains('if (!saved || !mounted'));
    expect(section, isNot(contains("SocketService.instance.editMessage(")));
  });

  test('duplicate and unauthenticated edits are rejected', () {
    final payload = PrivateE2eeEditProtocol.create(
      eventId: 'secure_edit_1124',
      from: 'alice',
      to: 'bob',
      targetMessageId: 'original_1124',
      newText: 'Updated',
      editedAt: DateTime.utc(2026, 11, 8, 12),
    );

    final original = <String, dynamic>{
      'id': 'original_1124',
      'from': 'alice',
      'to': 'bob',
      'e2ee': true,
    };

    bool valid(String sender) => PrivateE2eeEditProtocol.canApply(
      payload: payload,
      original: original,
      authenticatedFrom: sender,
      localUser: 'bob',
      peer: 'alice',
    );

    expect(valid('mallory'), isFalse);
    expect(valid('alice'), isTrue);

    original['lastEditEventId'] = payload['id'];
    expect(valid('alice'), isFalse);
  });
}