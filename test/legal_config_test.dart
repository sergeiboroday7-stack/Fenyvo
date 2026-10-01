import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/config/legal_config.dart';

void main() {
  test('legal document versions and minimum age stay aligned', () {
    expect(LegalConfig.termsVersion, '2026-10-01');
    expect(LegalConfig.privacyVersion, '2026-10-01');
    expect(LegalConfig.minimumAge, 16);
    expect(LegalConfig.termsUri.scheme, 'https');
    expect(LegalConfig.privacyUri.scheme, 'https');
  });
}
