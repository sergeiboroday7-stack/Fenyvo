import 'dart:async';

import 'package:flutter/material.dart';

import '../features/messages/domain/voice_duration_formatter.dart';
import '../theme/fenyvo_theme.dart';

/// UI only. The parent chat owns microphone recording and message sending.
class PrivateVoiceRecordingComposer extends StatelessWidget {
  const PrivateVoiceRecordingComposer({
    super.key,
    required this.replyPreview,
    required this.duration,
    this.languageCode = 'ru',
    required this.onCancel,
    required this.onSend,
  });

  final Widget replyPreview;
  final Duration duration;
  final String languageCode;
  final Future<void> Function() onCancel;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final tick = duration.inMilliseconds ~/ 250;

    final language = languageCode.toLowerCase().split(RegExp(r'[-_]')).first;

    final cancelTooltip = switch (language) {
      'uk' => 'Скасувати',
      'en' => 'Cancel',
      _ => 'Отменить',
    };

    final sendTooltip = switch (language) {
      'uk' => 'Надіслати',
      'en' => 'Send',
      _ => 'Отправить',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        replyPreview,
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const BoxDecoration(color: FenyvoPalette.surface),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFF5252),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    VoiceDurationFormatter.format(duration),
                    style: const TextStyle(
                      color: FenyvoPalette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(18, (index) {
                        final height =
                            7.0 + ((index * 11 + tick * 3) % 24).toDouble();

                        return Expanded(
                          child: Align(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              height: height,
                              decoration: BoxDecoration(
                                color: FenyvoPalette.blue,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: cancelTooltip,
                  onPressed: () {
                    unawaited(onCancel());
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFF6B6B),
                  ),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [FenyvoPalette.blue, FenyvoPalette.blueDeep],
                    ),
                  ),
                  child: IconButton(
                    tooltip: sendTooltip,
                    onPressed: () {
                      unawaited(onSend());
                    },
                    icon: const Icon(
                      Icons.send_rounded,
                      color: FenyvoPalette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
