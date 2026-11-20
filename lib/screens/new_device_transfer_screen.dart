import '../widgets/device_transfer_failure_panel.dart';
import '../widgets/device_transfer_code_input.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import '../config/server_config.dart';
import '../services/crypto/old_device_pin.dart';
import '../services/crypto/device_transfer_candidate_store.dart';
import '../services/new_device_transfer_v2_client.dart';
import '../widgets/device_transfer_pairing_screen.dart';

class NewDeviceTransferScreen extends StatefulWidget {
  const NewDeviceTransferScreen({
    super.key,
    required this.username,
    required this.password,
    required this.language,
  });
  final String username, password, language;
  @override
  State<NewDeviceTransferScreen> createState() =>
      _NewDeviceTransferScreenState();
}

class _NewDeviceTransferScreenState extends State<NewDeviceTransferScreen> {
  final _pin = TextEditingController();
  NewDeviceTransferV2Client? _client;
  bool _busy = false;
  String? _error;
  String? _localKeyDiagnostic;
  String t(String ru, String uk, String en) =>
      transferText(widget.language, ru, uk, en);
  Future<void> start() async {
    if (_busy ||
        (_client != null && _client!.phase != TransferV2Phase.interrupted))
      return;
    // A fresh client resumes the same sealed candidate after interruption.
    if (_client?.phase == TransferV2Phase.interrupted) {
      _client!.removeListener(update);
      _client!.dispose();
      _client = null;
    }
    // Stage names are internal only; never display raw errors or transfer data.
    var stage = 'code';
    setState(() {
      _busy = true;
      _error = null;
      _localKeyDiagnostic = null;
    });
    try {
      final pin = OldDevicePin.parse(_pin.text.trim());
      stage = 'account';
      if (pin.username != widget.username.trim()) {
        setState(
          () => _error = t(
            'Код переноса принадлежит другому аккаунту.',
            'Код перенесення належить іншому акаунту.',
            'This transfer code belongs to another account.',
          ),
        );
        return;
      }
      if (widget.password.isEmpty) {
        setState(
          () => _error = t(
            'Не указан пароль аккаунта. Вернись к экрану входа.',
            'Не вказано пароль акаунта. Повернися до екрана входу.',
            'Account password is missing. Return to sign-in.',
          ),
        );
        return;
      }
      // Read-only: existing E2EE identities must never be overwritten.
      stage = 'local_identity';
      final localKeyState = await DeviceTransferCandidateStore(widget.username)
          .diagnoseExistingLocalIdentity(pin);
      if (!mounted) return;
      if (localKeyState != 'NO_LOCAL_IDENTITY' &&
          localKeyState != 'RESUMABLE_TRANSFER_IDENTITY') {
        setState(() => _localKeyDiagnostic = localKeyState);
        return;
      }
      stage = 'transfer';
      final client = NewDeviceTransferV2Client(
        server: ServerConfig.websocketUri,
        pin: pin,
      );
      _client = client;
      client.addListener(update);
      // Keep the code in the field for diagnosis; never log or display it.
      setState(() {});
      await client.run(password: widget.password);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = switch (stage) {
          'code' => t(
            'Неверный формат кода переноса. Получи новый код со старого телефона.',
            'Неправильний формат коду перенесення. Отримай новий код зі старого телефона.',
            'Invalid transfer code format. Get a new code from the old phone.',
          ),
          'local_identity' => t(
            'Не удалось проверить защищённые ключи этого телефона. Данные не изменены.',
            'Не вдалося перевірити захищені ключі цього телефона. Дані не змінено.',
            'Could not inspect protected keys on this phone. No data was changed.',
          ),
          'transfer' => t(
            'Не удалось начать перенос. Проверь соединение и данные входа; ключи не удаляй.',
            'Не вдалося розпочати перенесення. Перевір з’єднання й дані входу; не видаляй ключі.',
            'Could not start transfer. Check the connection and sign-in details; do not delete keys.',
          ),
          _ => t(
            'Не удалось проверить данные аккаунта.',
            'Не вдалося перевірити дані акаунту.',
            'Could not validate account details.',
          ),
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _returning = false;
  void update() {
    if (!mounted) return;
    setState(() {});
    if (_client?.phase == TransferV2Phase.ready && !_returning) {
      _returning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        TransferredDeviceConnection? connection;
        try {
          connection = _client!.takeConnection();
          Navigator.of(context).pop(connection);
        } catch (_) {
          if (connection != null) {
            unawaited(connection.abort());
          }
          _returning = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _client?.removeListener(update);
    _client?.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _client?.phase;
    final verified = phase == TransferV2Phase.ready;
    final candidate = _client?.candidate;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            'Подключить новый телефон',
            'Підключити новий телефон',
            'Connect new phone',
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                'Получи код непосредственно со своего старого телефона. Не используй код, присланный незнакомцем.',
                'Отримай код безпосередньо зі свого старого телефона. Не використовуй код, надісланий незнайомцем.',
                'Get the code directly from your own old phone. Do not use a code supplied by a stranger.',
              ),
            ),
            const SizedBox(height: 12),
            DeviceTransferCodeInput(
              controller: _pin,
              username: widget.username,
              language: widget.language,
              enabled:
                  (_client == null || phase == TransferV2Phase.interrupted) &&
                  !_busy,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  (_client == null || phase == TransferV2Phase.interrupted) &&
                      !_busy
                  ? start
                  : null,
              child: Text(
                t(
                  'Запросить перенос',
                  'Запросити перенесення',
                  'Request transfer',
                ),
              ),
            ),
            if (candidate != null) ...[
              const SizedBox(height: 16),
              Text(
                t(
                  'Сравни весь этот код со старым телефоном:',
                  'Порівняй увесь цей код зі старим телефоном:',
                  'Compare this entire code with the old phone:',
                ),
              ),
              SelectableText(
                sha256.convert(base64Decode(candidate.identityKey)).toString(),
              ),
            ],
            if (_busy || phase == TransferV2Phase.staging)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            if (phase == TransferV2Phase.waiting)
              Text(
                t(
                  'Ожидаем подтверждение на старом телефоне',
                  'Очікуємо підтвердження на старому телефоні',
                  'Waiting for approval on the old phone',
                ),
              ),
            if (verified)
              Text(
                t(
                  'Перенос подтверждён. Открываем защищённый чат.',
                  'Перенесення підтверджено. Відкриваємо захищений чат.',
                  'Transfer confirmed. Opening the encrypted chat.',
                ),
              ),
            if (phase == TransferV2Phase.interrupted)
              DeviceTransferFailurePanel(
                failure: _client?.failure,
                language: widget.language,
              ),
            if (_localKeyDiagnostic != null) ...[
              const SizedBox(height: 12),
              Text(
                _localKeyDiagnostic == 'MATCHES_OLD_DEVICE'
                    ? t(
                        'На этом телефоне уже сохранён ключ, совпадающий с ключом старого телефона. Перенос остановлен: требуется отдельное подтверждённое восстановление входа. Данные не изменены.',
                        'На цьому телефоні вже збережено ключ, що збігається з ключем старого телефона. Перенесення зупинено: потрібне окреме підтверджене відновлення входу. Дані не змінено.',
                        'This phone already holds an identity matching the old phone. Transfer is stopped: a separate authenticated sign-in recovery is required. No data was changed.',
                      )
                    : _localKeyDiagnostic == 'DIFFERS_FROM_OLD_DEVICE'
                    ? t(
                        'На этом телефоне сохранён другой E2EE-ключ. Автоматическая замена запрещена. Не очищай данные: требуется безопасный сценарий восстановления.',
                        'На цьому телефоні збережено інший E2EE-ключ. Автоматичну заміну заборонено. Не очищуй дані: потрібне безпечне відновлення.',
                        'A different E2EE identity exists on this phone. Automatic replacement is forbidden. Do not clear app data; safe recovery is required.',
                      )
                    : t(
                        'Данные аккаунта не совпадают. Перенос не запущен.',
                        'Дані облікового запису не збігаються. Перенесення не розпочато.',
                        'Account details do not match. Transfer was not started.',
                      ),
              ),
              SelectableText('LOCAL_KEY_' + _localKeyDiagnostic!),
            ],
            if (_localKeyDiagnostic == 'MATCHES_OLD_DEVICE') ...[
              const SizedBox(height: 12),
              Text(
                t(
                  'Вернись к экрану входа и войди с данными существующего аккаунта. Эта кнопка не переносит и не изменяет ключи.',
                  'Повернись до екрана входу та увійди з даними наявного акаунта. Ця кнопка не переносить і не змінює ключі.',
                  'Return to sign-in and use your existing account credentials. This button does not transfer or change keys.',
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.login),
                label: Text(
                  t(
                    'Вернуться ко входу',
                    'Повернутися до входу',
                    'Return to sign-in',
                  ),
                ),
              ),
            ], // LOCAL_KEY_RECOVERY_ACTION_6304_85
            if (_error != null) Text(_error!),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('Закрыть', 'Закрити', 'Close')),
            ),
          ],
        ),
      ),
    );
  }
}
