import 'package:flutter/material.dart';

import '../services/app_language_service.dart';
import '../services/crypto/signal_e2ee_service.dart';
import '../services/socket_service.dart';
import '../theme/fenyvo_theme.dart';
import 'device_transfer_pairing_screen.dart';

/// The old-device entry point; approval stays in DeviceTransferApprovalHost.
class DeviceTransferSettingsTile extends StatelessWidget {
  const DeviceTransferSettingsTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: AppLanguageService.instance.code,
    builder: (context, language, _) {
      String t(String ru, String uk, String en) => transferText(language, ru, uk, en);
      return ListTile(
        key: const ValueKey('device-transfer-settings'),
        leading: const Icon(Icons.phonelink_ring, color: FenyvoPalette.gold),
        title: Text(t('Перенос аккаунта', 'Перенесення акаунта', 'Transfer account'),
          style: const TextStyle(color: FenyvoPalette.ink)),
        subtitle: Text(t('На новый телефон · QR-код и подтверждение',
          'На новий телефон · QR-код і підтвердження',
          'To a new phone · QR code and approval'),
          style: const TextStyle(color: FenyvoPalette.secondary, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: FenyvoPalette.secondary),
        onTap: () {
          final socket = SocketService.instance;
          final owner = socket.currentUser, accountId = socket.currentAccountId;
          final generation = socket.deviceTransferSessionGeneration;
          if (owner == null || accountId == null || !socket.isAuthenticated) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(
              'Подключись к серверу и повтори.', 'Підключись до сервера та повтори.',
              'Connect to the server and try again.'))));
            return;
          }
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => DeviceTransferPairingScreen(
              language: language,
              loadPin: () => SignalE2eeService.instance.deviceTransferPublicPin(
                accountId: accountId,
                username: owner,
                isSessionCurrent: () => socket.isAuthenticated &&
                  socket.currentUser == owner && socket.currentAccountId == accountId &&
                  socket.deviceTransferSessionGeneration == generation,
              ),
            ),
          ));
        },
      );
    },
  );
}
