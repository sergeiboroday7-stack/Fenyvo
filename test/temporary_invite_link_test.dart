import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/temporary_invite_link.dart';

void main() {
  final token = 'a'.padRight(64, 'a');
  test('canonical link can be copied and parsed', () {
    final link = TemporaryInviteLink.urlForToken(token);
    expect(link, 'https://fenyvo.com/t/$token');
    expect(TemporaryInviteLink.tokenFromText(link), token);
    expect(TemporaryInviteLink.tokenFromUri(Uri.parse(link)), token);
  });
  test('manual hexadecimal token is accepted', () {
    expect(TemporaryInviteLink.tokenFromText(token.toUpperCase()), token);
  });
  test('other hosts cannot masquerade as invitations', () {
    expect(
      TemporaryInviteLink.tokenFromText('https://evil.example/t/$token'),
      isNull,
    );
    expect(
      TemporaryInviteLink.tokenFromText(
        'https://fenyvo.com.evil.example/t/$token',
      ),
      isNull,
    );
  });
  test('plaintext and non-HTTPS links are rejected', () {
    expect(
      TemporaryInviteLink.tokenFromText('http://fenyvo.com/t/$token'),
      isNull,
    );
    expect(TemporaryInviteLink.tokenFromText('fenyvo.com/t/$token'), isNull);
    expect(TemporaryInviteLink.tokenFromText('fenyvo://t/$token'), isNull);
  });
  test('extra segments, query and fragment are rejected', () {
    expect(
      TemporaryInviteLink.tokenFromText('https://fenyvo.com/t/$token/extra'),
      isNull,
    );
    expect(
      TemporaryInviteLink.tokenFromText(
        'https://fenyvo.com/t/$token?redirect=evil',
      ),
      isNull,
    );
    expect(
      TemporaryInviteLink.tokenFromText('https://fenyvo.com/t/$token#extra'),
      isNull,
    );
  });
  test('userinfo and nondefault ports are rejected', () {
    expect(
      TemporaryInviteLink.tokenFromText('https://user@fenyvo.com/t/$token'),
      isNull,
    );
    expect(
      TemporaryInviteLink.tokenFromText('https://fenyvo.com:8443/t/$token'),
      isNull,
    );
  });
  test('invalid token cannot create URL or initiate join', () {
    expect(TemporaryInviteLink.tokenFromText('xyz'), isNull);
    expect(() => TemporaryInviteLink.urlForToken('xyz'), throwsFormatException);
  });
  test('correct host but permanent contact link is not temporary', () {
    expect(
      TemporaryInviteLink.tokenFromText('https://fenyvo.com/u/testuser'),
      isNull,
    );
  });
}
