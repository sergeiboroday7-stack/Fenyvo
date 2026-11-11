import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_external_text_policy.dart';

void main() {
  test('blocks E2EE-protected message', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(
        isChatE2eeActive: false,
        <String, dynamic>{'text': 'secret', 'e2ee': true},
      ),
      isFalse,
    );
  });

  test('allows an explicitly unencrypted message', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(
        isChatE2eeActive: false,
        <String, dynamic>{'text': 'hello', 'e2ee': false},
      ),
      isTrue,
    );
  });

  test('allows legacy plain text without the E2EE flag', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(
        isChatE2eeActive: false,
        <String, dynamic>{'text': 'hello'},
      ),
      isTrue,
    );
  });

  test('blocks string-encoded true E2EE flag', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(
        isChatE2eeActive: false,
        <String, dynamic>{'text': 'secret', 'e2ee': 'true'},
      ),
      isFalse,
    );
  });

  test('blocks message containing E2EE media metadata', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(
        isChatE2eeActive: false,
        <String, dynamic>{
          'text': 'attachment',
          'e2eeMedia': <String, dynamic>{'version': 1},
        },
      ),
      isFalse,
    );
  });
  test('blocks ordinary text when chat E2EE is active', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(<String, dynamic>{
        'text': 'older plain message',
        'e2ee': false,
      }, isChatE2eeActive: true),
      isFalse,
    );
  });

  test('blocks protected message in active E2EE chat', () {
    expect(
      PrivateExternalTextPolicy.canSendMessage(<String, dynamic>{
        'text': 'secret',
        'e2ee': true,
      }, isChatE2eeActive: true),
      isFalse,
    );
  });
}
