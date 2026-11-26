import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/temporary_chat_ui_guard.dart';

void main() {
  final session = List<String>.filled(48, 'a').join();
  final other = List<String>.filled(48, 'b').join();
  Map<String, dynamic> event({
    String? id,
    String role = 'owner',
    bool e2ee = true,
  }) => {
    'sessionId': id ?? session,
    'role': role,
    'messageId': 'm-1',
    'time': '2026-11-21T12:00:00Z',
    'text': 'ciphertext decrypted locally',
    'e2ee': e2ee,
    'e2eeVersion': 2,
    'e2eeProtocol': 'signal',
  };
  bool accepts(Map<String, dynamic> data) =>
      TemporaryChatUiGuard.acceptsMessage(
        sessionId: session,
        role: 'owner',
        data: data,
      );

  test('valid session and role only', () {
    expect(TemporaryChatUiGuard.validSession(session, 'owner'), isTrue);
    expect(TemporaryChatUiGuard.validSession(session, 'guest'), isTrue);
    expect(TemporaryChatUiGuard.validSession('invalid', 'owner'), isFalse);
    expect(TemporaryChatUiGuard.validSession(session, 'admin'), isFalse);
  });
  test('decrypted matching session is accepted', () {
    expect(accepts(event()), isTrue);
  });
  test('another session cannot reach this chat', () {
    expect(accepts(event(id: other)), isFalse);
  });
  test('another role cannot reach this chat', () {
    expect(accepts(event(role: 'guest')), isFalse);
  });
  test('raw or non-Signal messages are rejected', () {
    expect(accepts(event(e2ee: false)), isFalse);
    expect(accepts(event()..['e2eeProtocol'] = 'plain'), isFalse);
    expect(accepts(event()..['e2eeVersion'] = 1), isFalse);
  });
  test('empty message data is rejected', () {
    expect(accepts(event()..['text'] = ''), isFalse);
    expect(accepts(event()..['messageId'] = ''), isFalse);
  });
  bool live({
    bool authenticated = true,
    String? owner = 'alice',
    String? accountId = 'account-a',
    int generation = 8,
  }) => TemporaryChatUiGuard.live(
    authenticated: authenticated,
    expectedOwner: 'alice',
    activeOwner: owner,
    expectedAccountId: 'account-a',
    activeAccountId: accountId,
    expectedGeneration: 8,
    activeGeneration: generation,
  );
  test('scope accepts only current login', () {
    expect(live(), isTrue);
    expect(live(authenticated: false), isFalse);
    expect(live(owner: 'bob'), isFalse);
    expect(live(accountId: 'account-b'), isFalse);
    expect(live(accountId: null), isFalse);
    expect(live(generation: 9), isFalse);
  });
}
