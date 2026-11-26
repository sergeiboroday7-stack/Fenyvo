import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/private_chat_message_links.dart';

void main() {
  const token = 'abcdef0123456789' 'abcdef0123456789'
      'abcdef0123456789' 'abcdef0123456789';

  test('temporary invitation in encrypted message gets an explicit action', () {
    final links = PrivateChatMessageLink.extract(
      'Привет! https://fenyvo.com/t/$token. Подключись, пожалуйста.',
    );
    expect(links, hasLength(1));
    expect(links.single.kind, PrivateChatMessageLinkKind.temporaryInvite);
    expect(links.single.temporaryToken, token);
    expect(links.single.uri.toString(), 'https://fenyvo.com/t/$token');
  });

  test('invalid temporary tokens are never treated as generic links', () {
    expect(
      PrivateChatMessageLink.extract('https://fenyvo.com/t/invalid-token'),
      isEmpty,
    );
    expect(
      PrivateChatMessageLink.extract('https://fenyvo.com/t/$token?x=1'),
      isEmpty,
    );
  });

  test('permanent contacts and external https links stay distinct', () {
    final links = PrivateChatMessageLink.extract(
      'https://fenyvo.com/u/Alice_3 https://example.org/guide',
    );
    expect(links, hasLength(2));
    expect(links.first.kind, PrivateChatMessageLinkKind.contact);
    expect(links.first.contactUsername, 'Alice_3');
    expect(links.last.kind, PrivateChatMessageLinkKind.external);
  });

  test('reject spoofed hosts and duplicate links', () {
    final links = PrivateChatMessageLink.extract(
      'https://fenyvo.com.evil.test/t/$token '
      'https://fenyvo.com/t/$token https://fenyvo.com/t/$token',
    );
    expect(links.where((e) => e.kind == PrivateChatMessageLinkKind.temporaryInvite),
        hasLength(1));
    expect(links, hasLength(2));
  });

  test('plain text and non-https schemes do not create link actions', () {
    expect(PrivateChatMessageLink.extract('just a message'), isEmpty);
    expect(PrivateChatMessageLink.extract('javascript:alert(1)'), isEmpty);
    expect(PrivateChatMessageLink.extract('http://fenyvo.com/u/Alice'), isEmpty);
  });
}
