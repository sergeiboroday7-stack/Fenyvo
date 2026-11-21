import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legal migration blocks chat navigation until accepted', () {
    final auth = File('lib/screens/auth_screen.dart').readAsStringSync();
    final login = auth.substring(
      auth.indexOf("if (type == 'login_success')"),
      auth.indexOf("if (type == 'register_success')"),
    );
    expect(login, contains("data['legalRequired'] == true"));
    expect(login, contains('_showLegalMigrationPrompt()'));
    expect(login, contains("type == 'legal_acceptance_success'"));
    expect(login, contains("type == 'legal_acceptance_error'"));
    expect(auth, contains('barrierDismissible: false'));
    expect(auth, contains('acceptedDocuments && confirmedAge'));
    expect(auth, contains('LegalConfig.termsVersion'));
    expect(auth, contains('LegalConfig.privacyVersion'));
  });

  test('socket sends explicit acceptance to server', () {
    final socket = File('lib/services/socket_service.dart').readAsStringSync();
    expect(socket, contains('bool acceptLegal({'));
    expect(socket, contains("_send('accept_legal', {"));
    expect(socket, contains("'termsAccepted': termsAccepted"));
    expect(socket, contains("'ageConfirmed': ageConfirmed"));
  });
}
