import 'package:flutter_test/flutter_test.dart';
import '../lib/services/app_language_service.dart';
import '../lib/services/temporary_trust_l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = AppLanguageService.instance;
  final original = service.code.value;
  tearDown(() => service.code.value = original);

  test('temporary chat UI follows selected Russian, Ukrainian and English', () {
    service.code.value = 'ru';
    expect(TemporaryTrustL10n.text('Создать ссылку'), 'Создать ссылку');
    service.code.value = 'uk';
    expect(TemporaryTrustL10n.text('Создать ссылку'), 'Створити посилання');
    service.code.value = 'en';
    expect(TemporaryTrustL10n.text('Создать ссылку'), 'Create link');
  });

  test('dynamic counters preserve exact count', () {
    service.code.value = 'en';
    expect(TemporaryTrustL10n.text('Активные чаты: 12'), 'Active chats: 12');
    expect(TemporaryTrustL10n.text('3 · 2 ждут'), '3 · 2 pending');
    service.code.value = 'uk';
    expect(TemporaryTrustL10n.text('Непрочитанных: 4'), 'Непрочитаних: 4');
  });

  test('selected additional languages show translated core labels', () {
    service.code.value = 'de';
    expect(TemporaryTrustL10n.text('Создать ссылку'), 'Link erstellen');
    service.code.value = 'pl';
    expect(TemporaryTrustL10n.text('Временные контакты'), 'Kontakty tymczasowe');
    service.code.value = 'ja';
    expect(TemporaryTrustL10n.text('Поделиться'), '共有');
  });

  test('unknown texts are never automatically rewritten', () {
    service.code.value = 'en';
    expect(TemporaryTrustL10n.text('hello confidential note'), 'hello confidential note');
  });
}
