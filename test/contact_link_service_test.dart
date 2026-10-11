import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/contact_link_service.dart';

void main() {
  test('extracts a valid Fenyvo contact username', () {
    final username = ContactLinkService.usernameFromUri(
      Uri.parse('https://fenyvo.com/u/SpartaFenix'),
    );

    expect(username, 'SpartaFenix');
  });

  test('accepts supported Cyrillic usernames', () {
    final username = ContactLinkService.usernameFromUri(
      Uri.parse('https://fenyvo.com/u/%D0%A1%D0%B5%D1%80%D0%B3%D0%B5%D0%B9_1'),
    );

    expect(username, 'Сергей_1');
  });

  test('rejects foreign hosts and malformed contact paths', () {
    expect(
      ContactLinkService.usernameFromUri(
        Uri.parse('https://example.com/u/SpartaFenix'),
      ),
      isNull,
    );
    expect(
      ContactLinkService.usernameFromUri(Uri.parse('https://fenyvo.com/u/a')),
      isNull,
    );
    expect(
      ContactLinkService.usernameFromUri(
        Uri.parse('https://fenyvo.com/download/app.apk'),
      ),
      isNull,
    );
  });
}
