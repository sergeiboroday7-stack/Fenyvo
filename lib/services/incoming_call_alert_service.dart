import 'dart:io';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android owns ringtone audio routing and vibration, not the WebRTC stream.
/// Other platforms are deliberately unchanged in this release.
class IncomingCallAlertService {
  IncomingCallAlertService._()
    : _channel = const MethodChannel('spartan_chat/incoming_call_alert'),
      _supported = !kIsWeb && (Platform.isAndroid || Platform.isWindows),
      _windows = !kIsWeb && Platform.isWindows;

  @visibleForTesting
  IncomingCallAlertService.forTesting({
    required MethodChannel channel,
    bool supported = true,
  }) : _channel = channel,
       _supported = supported,
       _windows = false;

  static final instance = IncomingCallAlertService._();
  final MethodChannel _channel;
  final bool _supported;
  final bool _windows;
  AudioPlayer? _player;
  Future<void> _audioQueue = Future<void>.value();
  Timer? _watchdog;
  String? _activeCallId;

  Future<void> start(String callId) async {
    if (!_supported || callId.isEmpty || _activeCallId == callId) return;
    _activeCallId = callId;
    if (_windows) {
      _audioQueue = _audioQueue
          .then((_) async {
            if (_activeCallId != callId) return;
            final player = _player ??= AudioPlayer();
            await player.setReleaseMode(ReleaseMode.loop);
            if (_activeCallId != callId) return;
            await player.play(
              AssetSource('sounds/spartan_phoenix_call.wav'),
              volume: 0.75,
            );
            if (_activeCallId != callId) await player.stop();
          })
          .catchError((Object _) {
            debugPrint('Windows ringtone unavailable');
          });
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 75), () {
        if (_activeCallId == callId) unawaited(stop());
      });
      await _audioQueue;
      return;
    }
    try {
      await _channel.invokeMethod<void>('start', {'callId': callId});
    } catch (_) {
      // Failure to alert must never prevent accepting an incoming call.
      debugPrint('Incoming call alert is unavailable');
    }
  }

  Future<void> stop() async {
    final callId = _activeCallId;
    _activeCallId = null;
    _watchdog?.cancel();
    if (!_supported || callId == null) return;
    if (_windows) {
      _audioQueue = _audioQueue
          .then((_) async {
            await _player?.stop();
          })
          .catchError((Object _) {
            debugPrint('Windows ringtone stop unavailable');
          });
      await _audioQueue;
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop', {'callId': callId});
    } catch (_) {
      debugPrint('Incoming call alert stop could not reach the platform');
    }
  }
}
