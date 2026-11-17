import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/turn_credential_service.dart';

void main() {
  tearDown(() => TurnCredentialService.configure(null));

  test('uses all ICE candidates when TURN is unavailable', () {
    TurnCredentialService.configure(null);

    expect(TurnCredentialService.hasTurn, isFalse);
    expect(TurnCredentialService.iceTransportPolicy, 'all');
    expect(TurnCredentialService.iceServers, hasLength(1));
  });

  test('forces relay after valid TURN credentials are configured', () {
    TurnCredentialService.configure({
      'urls': [
        'turn:217.60.78.220:3478?transport=udp',
        'turn:217.60.78.220:3478?transport=tcp',
      ],
      'username': 'expires:user',
      'credential': 'secret',
    });

    expect(TurnCredentialService.hasTurn, isTrue);
    expect(TurnCredentialService.iceTransportPolicy, 'relay');
    expect(TurnCredentialService.iceServers, hasLength(2));
  });

  test('does not force relay for incomplete TURN credentials', () {
    TurnCredentialService.configure({
      'urls': ['turn:217.60.78.220:3478?transport=udp'],
      'username': '',
      'credential': '',
    });

    expect(TurnCredentialService.hasTurn, isFalse);
    expect(TurnCredentialService.iceTransportPolicy, 'all');
  });
}
