import 'dart:io';

import 'package:flutter/services.dart';

/// Audio amplitudes measured from the actual local video track.
///
/// One value represents approximately 100 milliseconds.
/// No microphone is activated and no audio is transmitted.
class HexVideoAudioLevels {
  static const MethodChannel _channel = MethodChannel('fenyvo/hex_video_audio');

  static const Duration interval = Duration(milliseconds: 100);

  static Future<List<double>> analyze(String path) async {
    if (!(Platform.isAndroid || Platform.isWindows) || path.trim().isEmpty) {
      return const <double>[];
    }

    try {
      final values = await _channel.invokeListMethod<double>(
        'analyze',
        <String, dynamic>{'path': path},
      );

      if (values == null) return const <double>[];

      return values
          .take(600)
          .map(
            (value) => value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0,
          )
          .toList(growable: false);
    } on PlatformException {
      return const <double>[];
    } on MissingPluginException {
      return const <double>[];
    }
  }

  static double atPosition(List<double> levels, Duration position) {
    if (levels.isEmpty) return 0.0;
    final index = position.inMilliseconds ~/ interval.inMilliseconds;
    if (index < 0 || index >= levels.length) return 0.0;
    return levels[index];
  }
}
