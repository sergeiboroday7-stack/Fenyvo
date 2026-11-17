import 'package:flutter/material.dart';

import '../services/device_transfer_diagnostics.dart';
import 'device_transfer_pairing_screen.dart';

class DeviceTransferFailurePanel extends StatelessWidget {
  const DeviceTransferFailurePanel({
    super.key,
    required this.failure,
    required this.language,
  });

  final TransferFailure? failure;
  final String language;

  @override
  Widget build(BuildContext context) {
    String t(String ru, String uk, String en) =>
        transferText(language, ru, uk, en);
    final message = switch (failure?.code) {
      TransferFailureCode.existingProfile => t(
        'На этом телефоне уже сохранён ключ этого аккаунта. Перенос остановлен, чтобы не заменить его. Не удаляй приложение и не очищай данные.',
        'На цьому телефоні вже збережено ключ цього акаунта. Перенесення зупинено, щоб не замінити його. Не видаляй застосунок і не очищай дані.',
        'This phone already stores a key for this account. Transfer stopped to avoid replacing it. Do not uninstall the app or clear its data.',
      ),
      TransferFailureCode.candidateConflict => t(
        'Сохранённая попытка переноса связана с другим кодом старого телефона. Данные сохранены; требуется проверка.',
        'Збережена спроба перенесення пов’язана з іншим кодом старого телефона. Дані збережено; потрібна перевірка.',
        'The saved transfer attempt uses a different old-phone code. Data was preserved; review is required.',
      ),
      TransferFailureCode.secureStorage => t(
        'Не удалось прочитать или сохранить защищённые данные переноса. Не очищай данные приложения.',
        'Не вдалося прочитати або зберегти захищені дані перенесення. Не очищай дані застосунку.',
        'Unable to read or persist secure transfer data. Do not clear app data.',
      ),
      TransferFailureCode.candidateInvalid => t(
        'Сохранённые данные переноса не прошли проверку. Они оставлены для восстановления.',
        'Збережені дані перенесення не пройшли перевірку. Їх залишено для відновлення.',
        'Saved transfer data failed validation. It has been retained for recovery.',
      ),
      TransferFailureCode.invalidInput => t(
        'Проверь данные входа. Защищённый запрос переноса не был начат.',
        'Перевір дані входу. Захищений запит перенесення не було розпочато.',
        'Check sign-in details. The secure transfer request was not started.',
      ),
      TransferFailureCode.timeout => t(
        'Истекло время ожидания на указанном ниже этапе. Проверь соединение и старый телефон.',
        'Час очікування на вказаному нижче етапі минув. Перевір з’єднання та старий телефон.',
        'The stage shown below timed out. Check the connection and old phone.',
      ),
      TransferFailureCode.connection => t(
        'Не удалось открыть соединение с сервером переноса.',
        'Не вдалося відкрити з’єднання із сервером перенесення.',
        'Unable to connect to the transfer server.',
      ),
      TransferFailureCode.responseRejected => t(
        'Ответ сервера не соответствует ожидаемому этапу. Проверь код ниже.',
        'Відповідь сервера не відповідає очікуваному етапу. Перевір код нижче.',
        'The server response did not match the expected stage. Review the code below.',
      ),
      TransferFailureCode.verification => t(
        'Проверка подтверждения переноса не пройдена. Защита от подмены остаётся включённой.',
        'Перевірку підтвердження перенесення не пройдено. Захист від підміни залишається увімкненим.',
        'Transfer verification failed. Protection against substitution remains enabled.',
      ),
      TransferFailureCode.localPreparation => t(
        'Не удалось подготовить локальный профиль для переноса. Данные не изменены.',
        'Не вдалося підготувати локальний профіль для перенесення. Дані не змінено.',
        'Unable to prepare the local transfer profile. No data was changed.',
      ),
      _ => t(
        'Перенос прерван. Сохрани код ошибки ниже для проверки.',
        'Перенесення перервано. Збережи код помилки нижче для перевірки.',
        'Transfer interrupted. Keep the error code below for review.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 12),
        SelectableText(failure?.diagnosticCode ?? 'DT_UNKNOWN'),
      ],
    );
  }
}
