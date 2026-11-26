import 'package:flutter/material.dart';

import 'chat_list_screen.dart';

/// Navigation only after server-confirmed Trust revocation. Never used by Back.
class TemporaryTrustEndNavigation {
  TemporaryTrustEndNavigation._();

  static bool _inProgress = false;

  static void toChats(BuildContext context, {required bool peerEnded}) {
    if (_inProgress) return;
    _inProgress = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => ChatListScreen(enigmaEnded: true, enigmaPeerEnded: peerEnded)),
      (_) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messenger.mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(peerEnded
                ? 'Чат окончен собеседником'
                : 'Чат завершён'),
            duration: const Duration(seconds: 5),
          ));
      }
      _inProgress = false;
    });
  }
}
