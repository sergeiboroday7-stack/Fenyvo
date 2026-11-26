import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/temporary_trust_message.dart';

void main() {
  test('Request and decline are exact human-readable messages', () {
    expect(
      TemporaryTrustMessage.parse(TemporaryTrustMessage.requestText)?.kind,
      TemporaryTrustKind.request,
    );
    expect(
      TemporaryTrustMessage.parse(TemporaryTrustMessage.declineText)?.kind,
      TemporaryTrustKind.decline,
    );
    expect(TemporaryTrustMessage.parse('My normal text'), isNull);
  });

  test('Own username can be voluntarily revealed', () {
    final text = TemporaryTrustMessage.revealTextFor('AllaAlla1');
    expect(text, isNotNull);
    final parsed = TemporaryTrustMessage.parse(text!);
    expect(parsed?.kind, TemporaryTrustKind.reveal);
    expect(parsed?.username, 'AllaAlla1');
  });

  test('Rejects unsafely formatted profile data', () {
    expect(TemporaryTrustMessage.revealTextFor('name\nother'), isNull);
    expect(TemporaryTrustMessage.revealTextFor(''), isNull);
    expect(
      TemporaryTrustMessage.revealTextFor(List.filled(100, 'a').join()),
      isNull,
    );
    expect(
      TemporaryTrustMessage.parse('${TemporaryTrustMessage.requestText} extra'),
      isNull,
    );
  });
}
