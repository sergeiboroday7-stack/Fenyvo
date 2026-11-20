import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/crypto/old_device_pin.dart';

String transferText(String language, String ru, String uk, String en) {
  final selected = language == 'system'
      ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
      : language;
  final code = selected.toLowerCase().split(RegExp('[-_]')).first;
  if (code == 'ru') return ru;
  if (code == 'uk' || code == 'ua') return uk;
  return en;
}

class DeviceTransferPairingScreen extends StatefulWidget {
  const DeviceTransferPairingScreen({
    super.key,
    required this.loadPin,
    required this.language,
  });
  final Future<OldDevicePin> Function() loadPin;
  final String language;
  @override
  State<DeviceTransferPairingScreen> createState() =>
      _DeviceTransferPairingScreenState();
}

class _DeviceTransferPairingScreenState
    extends State<DeviceTransferPairingScreen> {
  late final Future<OldDevicePin> _pin;
  @override
  void initState() {
    super.initState();
    _pin = widget.loadPin();
  }

  @override
  Widget build(BuildContext context) {
    String t(String ru, String uk, String en) =>
        transferText(widget.language, ru, uk, en);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t('Перенос аккаунта', 'Перенесення акаунта', 'Transfer account'),
        ),
      ),
      body: FutureBuilder<OldDevicePin>(
        future: _pin,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: Text(
                t(
                  'Не удалось подготовить перенос. Войди снова и повтори.',
                  'Не вдалося підготувати перенесення. Увійди знову та повтори.',
                  'Unable to prepare transfer. Sign in again and retry.',
                ),
              ),
            );
          final pin = snapshot.data;
          if (pin == null)
            return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  t(
                    'На новом телефоне открой экран входа → «Перенести аккаунт на это устройство» → «Сканировать QR». Наведи камеру на этот код. Затем запроси перенос и сравни код запроса на обоих телефонах перед подтверждением.',
                    'На новому телефоні відкрий екран входу → «Перенести акаунт на цей пристрій» → «Сканувати QR». Наведи камеру на цей код. Потім запроси перенесення та порівняй код запиту на обох телефонах перед підтвердженням.',
                    'On your new phone, open sign-in → Transfer account to this device → Scan QR. Point the camera at this code. Then request transfer and compare the request code on both phones before approving.',
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: pin.encode(), size: 240),
                ),
                const SizedBox(height: 12),
                Text(pin.username, style: Theme.of(context).textTheme.titleMedium),
                ExpansionTile(
                  title: Text(t('Код для ручного ввода', 'Код для ручного введення', 'Manual transfer code')),
                  children: [SelectableText(pin.encode())],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pin.encode()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t('Код скопирован', 'Код скопійовано', 'Code copied')),
                      ));
                    }
                  },
                  child: Text(
                    t('Копировать код', 'Копіювати код', 'Copy code'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
