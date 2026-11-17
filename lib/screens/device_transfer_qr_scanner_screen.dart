import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../widgets/device_transfer_pairing_screen.dart';

/// Reads public pairing data only. It cannot approve or activate a transfer.
class DeviceTransferQrScannerScreen extends StatefulWidget {
  const DeviceTransferQrScannerScreen({super.key, required this.language});
  final String language;

  @override
  State<DeviceTransferQrScannerScreen> createState() => _DeviceTransferQrScannerScreenState();
}

class _DeviceTransferQrScannerScreenState extends State<DeviceTransferQrScannerScreen> {
  bool _returned = false;
  String t(String ru, String uk, String en) => transferText(widget.language, ru, uk, en);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Сканировать QR', 'Сканувати QR', 'Scan QR'))),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Text(t(
        'Наведи камеру на QR в настройках переноса на старом телефоне.',
        'Наведи камеру на QR у налаштуваннях перенесення на старому телефоні.',
        'Point the camera at the transfer QR in Settings on your old phone.'))),
      Expanded(child: MobileScanner(
        // The widget owns its controller and handles app lifecycle and disposal.
        useAppLifecycleState: true,
        onDetect: (capture) {
          if (_returned || !mounted) return;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (barcode.format != BarcodeFormat.qrCode || value == null || value.isEmpty) continue;
            _returned = true;
            Navigator.of(context).pop(value);
            return;
          }
        },
        errorBuilder: (context, error) => Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t(
            'Камера недоступна. Разреши доступ к камере в настройках телефона или вставь код вручную.',
            'Камера недоступна. Дозволь доступ до камери в налаштуваннях телефона або встав код вручну.',
            'Camera unavailable. Allow camera access in phone settings or paste the code manually.'),
            textAlign: TextAlign.center),
        )),
      )),
      Padding(padding: const EdgeInsets.all(16), child: TextButton.icon(
        onPressed: () { if (!_returned) { _returned = true; Navigator.of(context).pop(); } },
        icon: const Icon(Icons.content_paste),
        label: Text(t('Ввести код вручную', 'Ввести код вручну', 'Enter code manually')),
      )),
    ])),
  );
}
