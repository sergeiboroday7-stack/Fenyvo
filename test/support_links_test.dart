import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/config/support_links.dart';

void main() {
  test('monobank support uses a public HTTPS jar link', () {
    final uri = SupportLinks.monobankJar;

    expect(uri.scheme, 'https');
    expect(uri.host, 'send.monobank.ua');
    expect(uri.pathSegments, ['jar', 'Aejkjg4K1k']);
    expect(uri.userInfo, isEmpty);
    expect(uri.query, isEmpty);
  });
}
