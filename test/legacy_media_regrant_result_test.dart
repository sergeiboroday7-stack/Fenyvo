import 'package:flutter_test/flutter_test.dart';
import '../lib/services/legacy_media_regrant_result.dart';

void main() {
  test('server approval is required', () {
    final approved = LegacyMediaRegrantResult.fromMessage(
      {'ok': true},
    );
    final denied = LegacyMediaRegrantResult.fromMessage(
      {'ok': false, 'reason': 'RECIPIENT_NOT_ELIGIBLE'},
    );

    expect(approved.approved, isTrue);
    expect(denied.approved, isFalse);
  });

  test('missing or malformed approval never succeeds', () {
    for (final message in <Map<String, dynamic>>[
      {},
      {'ok': 'true'},
      {'ok': 1},
      {'ok': null},
    ]) {
      expect(
        LegacyMediaRegrantResult.fromMessage(message).approved,
        isFalse,
      );
    }
  });

  test('recipient denial is localized in RU UK EN', () {
    final result = LegacyMediaRegrantResult.fromMessage({
      'ok': false,
      'reason': 'RECIPIENT_NOT_ELIGIBLE',
    });

    expect(result.localizedMessage('ru'), contains('контактом'));
    expect(result.localizedMessage('uk'), contains('контактом'));
    expect(result.localizedMessage('en'), contains('accepted contact'));
  });

  test('successful response is localized', () {
    final result = LegacyMediaRegrantResult.fromMessage({'ok': true});

    expect(result.localizedMessage('ru'), contains('предоставлен'));
    expect(result.localizedMessage('uk'), contains('надано'));
    expect(result.localizedMessage('en'), contains('granted'));
  });

  test('unknown server errors use safe localized fallback', () {
    final result = LegacyMediaRegrantResult.fromMessage({
      'ok': false,
      'reason': 'SOME_NEW_SERVER_ERROR',
    });

    expect(result.localizedMessage('ru'), isNotEmpty);
    expect(result.localizedMessage('uk'), isNotEmpty);
    expect(result.localizedMessage('en'), isNotEmpty);
    expect(result.approved, isFalse);
  });

  test('timeout and disconnect are localized in RU UK EN', () {
    for (final reason in ['TIMEOUT', 'DISCONNECTED']) {
      final result = LegacyMediaRegrantResult.fromMessage({
        'ok': false,
        'reason': reason,
      });

      for (final language in ['ru', 'uk', 'en']) {
        expect(
          result.localizedMessage(language),
          isNotEmpty,
        );
        expect(result.approved, isFalse);
      }
    }

    final timeout = LegacyMediaRegrantResult.fromMessage({
      'ok': false,
      'reason': 'TIMEOUT',
    });

    expect(timeout.localizedMessage('ru'), contains('Сервер'));
    expect(timeout.localizedMessage('uk'), contains('Сервер'));
    expect(timeout.localizedMessage('en'), contains('server'));
  });}