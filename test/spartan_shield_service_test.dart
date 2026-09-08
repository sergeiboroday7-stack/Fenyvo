import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/spartan_shield_service.dart';

void main() {
  test('detects an urgent request for a verification code in Russian', () {
    final result = SpartanShieldService.assess(
      'Срочно пришли код подтверждения',
    );

    expect(result, isNotNull);
    expect(result!.level, 'high');
  });

  test('detects an urgent request for money', () {
    final result = SpartanShieldService.assess(
      'Немедленно переведи деньги на эту карту',
    );

    expect(result, isNotNull);
    expect(result!.level, 'high');
  });

  test('detects a code request combined with a link', () {
    final result = SpartanShieldService.assess(
      'Введите код подтверждения на https://example.test',
    );

    expect(result, isNotNull);
    expect(result!.level, 'high');
  });

  test('does not warn for an ordinary message', () {
    expect(SpartanShieldService.assess('Привет, как дела?'), isNull);
  });
}
