import 'package:flutter/material.dart';

/// Forwards pointer gestures without owning recording or E2EE state.
class PrivateVoicePointerBridge extends StatelessWidget {
  const PrivateVoicePointerBridge({
    super.key,
    required this.enabled,
    required this.onMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<Offset> onMove;
  final VoidCallback onPointerUp;
  final VoidCallback onPointerCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (event) => onMove(event.position),
      onPointerUp: (_) => onPointerUp(),
      onPointerCancel: (_) => onPointerCancel(),
      child: child,
    );
  }
}
