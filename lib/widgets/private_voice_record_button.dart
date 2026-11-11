import 'package:flutter/material.dart';

import '../theme/fenyvo_theme.dart';

/// Voice recording button UI.
/// Recording ownership and gesture behavior stay with the parent chat.
class PrivateVoiceRecordButton extends StatelessWidget {
  const PrivateVoiceRecordButton({
    super.key,
    required this.tooltip,
    this.icon = Icons.mic_rounded,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;
  final GestureLongPressEndCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: FenyvoPalette.gold,
          ),
          child: Icon(icon, color: FenyvoPalette.onGold, size: 24),
        ),
      ),
    );
  }
}
