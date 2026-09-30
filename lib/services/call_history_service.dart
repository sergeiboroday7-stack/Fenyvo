import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'call_service.dart';
import 'socket_service.dart';
import 'call_clock.dart';

/// Observes calls without changing WebRTC or signaling.
class CallHistoryService {
  static String title(Map<String, dynamic> item) {
    final direction = item['incoming'] == true ? 'Входящий' : 'Исходящий';
    final kind = item['video'] == true ? 'видеозвонок' : 'аудиозвонок';
    return '$direction $kind';
  }

  static String status(Map<String, dynamic> item) {
    if (item['connected'] == true) {
      return CallClock.format(
        Duration(seconds: (item['seconds'] as num?)?.toInt() ?? 0),
      );
    }
    return switch (item['outcome']) {
      'missed' => 'Пропущенный звонок',
      'declined' => 'Отклонён',
      'cancelled' => 'Отменён',
      'failed' => item['reason']?.toString() ?? 'Не удалось соединиться',
      _ => 'Без соединения',
    };
  }

  static final changes = ValueNotifier<int>(0);
  static bool _initialized = false;
  static Map<String, dynamic>? _current;
  static String _owner = '';
  static Future<void> _writes = Future<void>.value();
  static List<Map<String, dynamic>> items(String owner) {
    final raw = Hive.box('spartan_call_history').get(owner);
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    CallService.instance.addListener(_observe);
  }

  static void _persist(Map<String, dynamic> value, String owner) {
    if (owner.isEmpty) return;
    _writes = _writes
        .then((_) async {
          final list = items(owner)..removeWhere((e) => e['id'] == value['id']);
          list.insert(0, value);
          await Hive.box('spartan_call_history')
              .put(owner, list.take(200).toList());
          changes.value++;
        })
        .catchError((Object error) {
          debugPrint('Не удалось сохранить историю звонков: $error');
        });
  }

  static void _observe() {
    final call = CallService.instance;
    if (call.phase == CallPhase.idle) {
      if (_current != null) {
        final item = Map<String, dynamic>.from(_current!);
        item['ended'] = true;
        _persist(item, _owner);
        _current = null;
      }
      return;
    }
    if (call.callId == null || call.peerUser == null) return;
    if (_current?['id'] != call.callId) {
      _owner = SocketService.instance.currentUser ?? '';
      _current = {
        'id': call.callId,
        'peer': call.peerUser,
        'video': call.isVideo,
        'incoming': call.isIncoming,
        'time': DateTime.now().toIso8601String(),
        'seconds': 0,
        'connected': false,
        'ended': false,
      };
      _persist(Map<String, dynamic>.from(_current!), _owner);
    }
    _current!['seconds'] = call.clock.elapsed.inSeconds;
    _current!['connected'] =
        _current!['connected'] == true || call.clock.connected;
    if (call.phase == CallPhase.ended) {
      _current!['ended'] = true;
      _current!['outcome'] = call.outcome?.name;
      _current!['reason'] = call.statusText;
      _persist(Map<String, dynamic>.from(_current!), _owner);
    }
  }
}
