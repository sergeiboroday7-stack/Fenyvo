import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presentation only: media tracks and call lifecycle remain in CallService.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.microphoneEnabled,
    required this.cameraEnabled,
    required this.isVideo,
    required this.canSwitchCamera,
    required this.onMicrophone,
    required this.onCamera,
    required this.onSwitchCamera,
    required this.onHangUp,
    this.onSpeakerphone,
    this.speakerphoneEnabled = false,
  });

  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool isVideo;
  final bool canSwitchCamera;
  final VoidCallback onMicrophone;
  final VoidCallback onCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onHangUp;
  final VoidCallback? onSpeakerphone;
  final bool speakerphoneEnabled;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onSpeakerphone != null)
        CallActionButton(
          key: const ValueKey('call-speaker-action'),
          icon: speakerphoneEnabled
              ? Icons.volume_up_rounded
              : Icons.hearing_rounded,
          label: 'Громкая связь',
          status: speakerphoneEnabled ? 'Включена' : 'Выключена',
          tooltip: speakerphoneEnabled
              ? 'Выключить громкую связь'
              : 'Включить громкую связь',
          toggled: speakerphoneEnabled,
          highlighted: speakerphoneEnabled,
          onPressed: onSpeakerphone!,
        ),
      CallActionButton(
        key: const ValueKey('call-microphone-action'),
        icon: microphoneEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
        label: 'Микрофон',
        status: microphoneEnabled ? 'Включён' : 'Выключен',
        tooltip: microphoneEnabled ? 'Выключить микрофон' : 'Включить микрофон',
        toggled: microphoneEnabled,
        highlighted: !microphoneEnabled,
        onPressed: onMicrophone,
      ),
      if (isVideo)
        CallActionButton(
          key: const ValueKey('call-camera-action'),
          icon: cameraEnabled
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          label: 'Камера',
          status: cameraEnabled ? 'Включена' : 'Выключена',
          tooltip: cameraEnabled ? 'Выключить камеру' : 'Включить камеру',
          toggled: cameraEnabled,
          highlighted: !cameraEnabled,
          onPressed: onCamera,
        ),
      if (isVideo && canSwitchCamera)
        CallActionButton(
          key: const ValueKey('call-switch-camera-action'),
          icon: Icons.cameraswitch_rounded,
          label: 'Сменить\nкамеру',
          tooltip: 'Переключить на другую камеру',
          onPressed: onSwitchCamera,
        ),
      CallActionButton(
        key: const ValueKey('call-hang-up-action'),
        icon: Icons.call_end_rounded,
        label: 'Завершить',
        tooltip: 'Завершить звонок',
        color: const Color(0xFFE53935),
        onPressed: onHangUp,
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
            final minimumWidth = 78 * textScale.clamp(1.0, 1.6);
            final fitting =
                ((constraints.maxWidth + gap) / (minimumWidth + gap)).floor();
            // Four controls use two balanced rows when one row cannot fit.
            final columns = fitting >= actions.length
                ? actions.length
                : math.max(1, math.min(actions.length == 5 ? 3 : 2, fitting));
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: 12,
              children: [
                for (final action in actions)
                  SizedBox(width: width, child: action),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CallActionButton extends StatelessWidget {
  const CallActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.status,
    this.toggled,
    this.highlighted = false,
    this.color = const Color(0xFF292929),
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final String? status;
  final bool? toggled;
  final bool highlighted;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Semantics(
      button: true,
      toggled: toggled,
      label: label.replaceAll('\n', ' '),
      value: status,
      onTapHint: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(16),
              focusColor: gold.withValues(alpha: 0.25),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: highlighted ? gold : color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: highlighted
                              ? const Color(0xFFFFE5A0)
                              : Colors.white24,
                          width: highlighted ? 2 : 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: highlighted
                            ? const Color(0xFF17130A)
                            : Colors.white,
                        size: 29,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        status!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: highlighted ? gold : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
