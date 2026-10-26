import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/fenyvo_shield_service.dart';

void main() {
  test('detects an urgent request for a verification code in Russian', () {
    final result = FenyvoShieldService.assess(
      'Срочно пришли код подтверждения',
    );

    expect(result, isNotNull);
    expect(result!.level, 'high');
  });

  test('detects an urgent request for money', () {
    final result = FenyvoShieldService.assess(
      'Немедленно переведи деньги на эту карту',
    );

    expect(result, isNotNull);
    expect(result!.level, 'high');
  });

  test('detects a code request combined with a link', () {
    final result = FenyvoShieldService.assess(
      'Введите код подтверждения на https://example.test',
    );

    expect(result, isNotNull);
    expect(result!.level, 'high');
  });

  test('does not warn for an ordinary message', () {
    expect(FenyvoShieldService.assess('Привет, как дела?'), isNull);
  });
}
