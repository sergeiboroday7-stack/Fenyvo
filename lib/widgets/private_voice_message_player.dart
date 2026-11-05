import 'dart:async';

import 'package:flutter/material.dart';

import '../features/messages/domain/voice_duration_formatter.dart';
import '../features/messages/domain/voice_playback_policy.dart';
import '../theme/fenyvo_theme.dart';

/// UI for a private voice message.
/// Playback ownership and resource cleanup remain with the parent chat.
class PrivateVoiceMessagePlayer extends StatelessWidget {
  const PrivateVoiceMessagePlayer({
    super.key,
    required this.message,
    required this.isMe,
    required this.messageId,
    required this.playingVoiceMessageId,
    required this.playbackPosition,
    required this.playbackDuration,
    required this.playbackRate,
    required this.isPlaying,
    required this.gold,
    required this.onToggle,
    required this.onSeek,
    required this.onCycleRate,
  });

  final Map<String, dynamic> message;
  final bool isMe;
  final String messageId;
  final String? playingVoiceMessageId;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final double playbackRate;
  final bool isPlaying;
  final Color gold;

  final Future<void> Function() onToggle;
  final Future<void> Function(double fraction) onSeek;
  final Future<void> Function() onCycleRate;

  @override
  Widget build(BuildContext context) {
    final selected = playingVoiceMessageId == messageId;

    final rawDuration = Duration(
      milliseconds: VoiceDurationFormatter.milliseconds(message),
    );

    final duration = selected && playbackDuration.inMilliseconds > 0
        ? playbackDuration
        : rawDuration;

    final position = selected ? playbackPosition : Duration.zero;

    final progress = VoicePlaybackPolicy.progress(position, duration);

    final foreground = isMe ? FenyvoPalette.ink : gold;

    final inactive = isMe
        ? FenyvoPalette.ink.withValues(alpha: 0.24)
        : FenyvoPalette.ink.withValues(alpha: 0.23);

    final secondaryText = isMe
        ? FenyvoPalette.ink.withValues(alpha: 0.58)
        : FenyvoPalette.ink.withValues(alpha: 0.62);

    final waveformSeed = messageId.hashCode.abs();

    const barCount = 36;

    return SizedBox(
      width: 272,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () {
              unawaited(onToggle());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected && isPlaying
                    ? foreground.withValues(alpha: 0.18)
                    : foreground.withValues(alpha: 0.10),
                border: Border.all(
                  color: foreground.withValues(alpha: selected ? 0.88 : 0.55),
                  width: selected ? 1.4 : 1.0,
                ),
              ),
              child: Icon(
                selected && isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: foreground,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 36,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      void seekAt(double x) {
                        final width = constraints.maxWidth;

                        if (width <= 0) {
                          return;
                        }

                        final fraction = (x / width).clamp(0.0, 1.0);

                        unawaited(onSeek(fraction));
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          seekAt(details.localPosition.dx);
                        },
                        onHorizontalDragUpdate: (details) {
                          seekAt(details.localPosition.dx);
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(barCount, (index) {
                            final mixed =
                                (waveformSeed + index * 31 + index * index * 7)
                                    .abs();

                            final height = 7.0 + (mixed % 25).toDouble();

                            final active = ((index + 1) / barCount) <= progress;

                            return Expanded(
                              child: Align(
                                alignment: Alignment.center,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 90),
                                  curve: Curves.easeOut,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 0.55,
                                  ),
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: active ? foreground : inactive,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${VoiceDurationFormatter.format(position)} / ${VoiceDurationFormatter.format(duration)}',
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        unawaited(onCycleRate());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: foreground.withValues(alpha: 0.34),
                          ),
                        ),
                        child: Text(
                          '${playbackRate.toStringAsFixed(playbackRate == 1.0 ? 0 : 1)}x',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
