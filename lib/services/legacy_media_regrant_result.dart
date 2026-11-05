/// A validated, localized response from the legacy media regrant protocol.
///
/// This class never decides access permissions. Only the authenticated
/// server can authorize a regrant.
class LegacyMediaRegrantResult {
  final bool approved;
  final String reason;

  const LegacyMediaRegrantResult({
    required this.approved,
    required this.reason,
  });

  factory LegacyMediaRegrantResult.fromMessage(
    Map<String, dynamic> message,
  ) {
    return LegacyMediaRegrantResult(
      approved: message['ok'] == true,
      reason: message['reason'] is String
          ? (message['reason'] as String)
          : 'REGRANT_FAILED',
    );
  }

  String localizedMessage(String languageCode) {
    final code = languageCode.toLowerCase().split('-').first;

    if (approved) {
      switch (code) {
        case 'uk':
          return 'Доступ до файлу надано.';
        case 'en':
          return 'File access granted.';
        default:
          return 'Доступ к файлу предоставлен.';
      }
    }

    final messages = <String, List<String>>{
      'UNAUTHENTICATED': [
        'Необходимо войти в аккаунт.',
        'Необхідно увійти до облікового запису.',
        'Please sign in.',
      ],
      'CONFIRMATION_REQUIRED': [
        'Необходимо подтвердить предоставление доступа.',
        'Необхідно підтвердити надання доступу.',
        'You must confirm access sharing.',
      ],
      'INVALID_OR_UNAPPROVED': [
        'Проверьте данные и подтверждение.',
        'Перевірте дані та підтвердження.',
        'Check the details and confirmation.',
      ],
      'NOT_OWNER_OR_NOT_FOUND': [
        'Файл не найден или вы не являетесь его владельцем.',
        'Файл не знайдено або ви не є його власником.',
        'File not found or you are not its owner.',
      ],
      'RECIPIENT_NOT_ELIGIBLE': [
        'Получатель не является подтверждённым контактом.',
        'Одержувач не є підтвердженим контактом.',
        'The recipient is not an accepted contact.',
      ],
      'TIMEOUT': [
        'Сервер не ответил вовремя. Попробуйте ещё раз.',
        'Сервер не відповів вчасно. Спробуйте ще раз.',
        'The server did not respond in time. Please try again.',
      ],
      'DISCONNECTED': [
        'Соединение потеряно. Повторите попытку после подключения.',
        'З’єднання втрачено. Повторіть спробу після підключення.',
        'Connection lost. Try again after reconnecting.',
      ],      'REVOKED': [
        'Доступ к этому файлу отозван.',
        'Доступ до цього файлу відкликано.',
        'Access to this file has been revoked.',
      ],
      'GROUP_GRANT_NOT_SUPPORTED': [
        'Групповой файл нельзя передать этим способом.',
        'Груповий файл не можна передати цим способом.',
        'Group files cannot be shared this way.',
      ],
    };

    final index = code == 'uk' ? 1 : (code == 'en' ? 2 : 0);
    final fallback = [
      'Не удалось предоставить доступ к файлу.',
      'Не вдалося надати доступ до файлу.',
      'Could not grant file access.',
    ];

    return (messages[reason] ?? fallback)[index];
  }
}