import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/device_transfer_qr_scanner_screen.dart';
import '../services/crypto/old_device_pin.dart';
import 'device_transfer_pairing_screen.dart';

typedef TransferCodeScanner = Future<String?> Function(BuildContext context);

class DeviceTransferCodeInput extends StatefulWidget {
  const DeviceTransferCodeInput({super.key, required this.controller,
    required this.username, required this.language, this.enabled = true, this.scanCode});
  final TextEditingController controller;
  final String username, language;
  final bool enabled;
  final TransferCodeScanner? scanCode;

  @override
  State<DeviceTransferCodeInput> createState() => _DeviceTransferCodeInputState();
}

class _DeviceTransferCodeInputState extends State<DeviceTransferCodeInput> {
  bool _reading = false;
  String? _error;
  String t(String ru, String uk, String en) => transferText(widget.language, ru, uk, en);
  bool get _cameraSupported => !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _read(bool camera) async {
    if (_reading || !widget.enabled) return;
    final expectedUser = widget.username;
    setState(() { _reading = true; _error = null; });
    try {
      final String? raw;
      if (camera) {
        raw = await (widget.scanCode?.call(context) ?? Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => DeviceTransferQrScannerScreen(language: widget.language))));
      } else {
        raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      }
      if (!mounted || !widget.enabled || expectedUser != widget.username) return;
      if (raw == null && camera) return;
      final pin = OldDevicePin.parse((raw ?? '').trim());
      if (pin.username != expectedUser.trim()) {
        if (mounted) setState(() => _error = t(
          'QR-код относится к другому аккаунту. Проверь имя входа.',
          'QR-код належить іншому акаунту. Перевір ім’я входу.',
          'This QR code belongs to a different account. Check the sign-in name.'));
        return;
      }
      widget.controller.text = pin.encode();
    } on FormatException {
      if (mounted) setState(() => _error = t(
        'QR-код не содержит корректные данные переноса FENYVO.',
        'QR-код не містить коректних даних перенесення FENYVO.',
        'The QR code does not contain valid FENYVO transfer data.'));
    } catch (_) {
      if (mounted) setState(() => _error = t(
        'Не удалось прочитать QR-код. Повтори сканирование.',
        'Не вдалося прочитати QR-код. Повтори сканування.',
        'Could not read the QR code. Try scanning again.'));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Wrap(spacing: 12, runSpacing: 8, children: [
      if (_cameraSupported || widget.scanCode != null)
        OutlinedButton.icon(
          key: const ValueKey('transfer-scan'),
          onPressed: widget.enabled && !_reading ? () => _read(true) : null,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(t('Сканировать QR', 'Сканувати QR', 'Scan QR')),
        ),
      TextButton.icon(
        key: const ValueKey('transfer-paste'),
        onPressed: widget.enabled && !_reading ? () => _read(false) : null,
        icon: const Icon(Icons.content_paste),
        label: Text(t('Вставить код', 'Вставити код', 'Paste code')),
      ),
    ]),
    TextField(
      controller: widget.controller,
      maxLines: 4,
      maxLength: 2048,
      enabled: widget.enabled && !_reading,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: t('Код старого телефона', 'Код старого телефона', 'Old phone code'),
        errorText: _error,
        errorMaxLines: 3,
      ),
    ),
  ]);
}
