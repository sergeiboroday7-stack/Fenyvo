import 'dart:async';

import 'package:flutter/foundation.dart';

import 'call_service.dart';
import 'group_call_service.dart';
import 'socket_service.dart';

enum FenyvoPulsePhase { idle, outgoing, incoming, matched }

class FenyvoPulse {
  const FenyvoPulse({
    required this.id,
    required this.from,
    required this.to,
    required this.video,
    required this.createdAt,
    required this.expiresAt,
    required this.state,
    this.acceptedAt,
    this.startsAt,
  });

  final String id;
  final String from;
  final String to;
  final bool video;
  final int createdAt;
  final int expiresAt;
  final String state;
  final int? acceptedAt;
  final int? startsAt;

  FenyvoPulse copyWith({String? state, int? acceptedAt, int? startsAt}) =>
      FenyvoPulse(
        id: id,
        from: from,
        to: to,
        video: video,
        createdAt: createdAt,
        expiresAt: expiresAt,
        state: state ?? this.state,
        acceptedAt: acceptedAt ?? this.acceptedAt,
        startsAt: startsAt ?? this.startsAt,
      );

  String peerFor(String currentUser) => from == currentUser ? to : from;

  int get windowMinutes =>
      ((expiresAt - createdAt) / Duration.millisecondsPerMinute)
          .round()
          .clamp(1, 24 * 60)
          .toInt();

  static int? _integer(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static FenyvoPulse? parse(Object? value) {
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    final id = data['id']?.toString().trim() ?? '';
    final from = data['from']?.toString().trim() ?? '';
    final to = data['to']?.toString().trim() ?? '';
    final createdAt = _integer(data['createdAt']);
    final expiresAt = _integer(data['expiresAt']);
    if (id.isEmpty ||
        from.isEmpty ||
        to.isEmpty ||
        createdAt == null ||
        expiresAt == null) {
      return null;
    }
    return FenyvoPulse(
      id: id,
      from: from,
      to: to,
      video: data['video'] == true,
      createdAt: createdAt,
      expiresAt: expiresAt,
      state: data['state']?.toString() ?? 'pending',
      acceptedAt: _integer(data['acceptedAt']),
      startsAt: _integer(data['startsAt']),
    );
  }
}

typedef PulseSender = void Function(String type, Map<String, dynamic> data);
typedef PulseCallStarter = Future<void> Function(String peer, bool video);

class PulseService extends ChangeNotifier {
  PulseService._({
    required PulseSender send,
    required String Function() currentUser,
    required bool Function() callBusy,
    required PulseCallStarter startCall,
    int Function()? now,
  }) : _send = send,
       _currentUser = currentUser,
       _callBusy = callBusy,
       _startCall = startCall,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  @visibleForTesting
  PulseService.forTesting({
    required PulseSender send,
    required String Function() currentUser,
    required bool Function() callBusy,
    required PulseCallStarter startCall,
    int Function()? now,
  }) : this._(
         send: send,
         currentUser: currentUser,
         callBusy: callBusy,
         startCall: startCall,
         now: now,
       );

  static final PulseService instance = PulseService._(
    send: SocketService.instance.sendPulse,
    currentUser: () => SocketService.instance.currentUser ?? '',
    callBusy: () =>
        CallService.instance.hasCall || GroupCallService.instance.hasCall,
    startCall: (peer, video) =>
        CallService.instance.startCall(peer: peer, video: video),
  );

  final PulseSender _send;
  final String Function() _currentUser;
  final bool Function() _callBusy;
  final PulseCallStarter _startCall;
  final int Function() _now;

  bool _initialized = false;
  Timer? _startTimer;
  Timer? _tickTimer;

  FenyvoPulsePhase phase = FenyvoPulsePhase.idle;
  FenyvoPulse? current;
  final List<FenyvoPulse> _pulses = <FenyvoPulse>[];
  final Set<String> _seenIncomingIds = <String>{};
  String? notice;
  int noticeSerial = 0;

  bool get hasPulse => phase != FenyvoPulsePhase.idle && current != null;
  List<FenyvoPulse> get pulses => List<FenyvoPulse>.unmodifiable(_pulses);
  int get requestCount => _pulses.length;
  int get unreadCount {
    final user = _currentUser();
    return _pulses
        .where(
          (pulse) =>
              pulse.to == user &&
              pulse.state == 'pending' &&
              !_seenIncomingIds.contains(pulse.id),
        )
        .length;
  }

  int get countdownSeconds {
    final startsAt = current?.startsAt;
    if (phase != FenyvoPulsePhase.matched || startsAt == null) return 0;
    final remaining = startsAt - _now();
    if (remaining <= 0) return 0;
    return (remaining / 1000).ceil();
  }

  int remainingMinutes(FenyvoPulse pulse) {
    final remaining = pulse.expiresAt - _now();
    if (remaining <= 0) return 0;
    return (remaining / Duration.millisecondsPerMinute).ceil();
  }

  FenyvoPulse? activeFor(String peer) {
    final value = current;
    if (value == null || value.peerFor(_currentUser()) != peer) return null;
    return value;
  }

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    SocketService.instance.addMessageHandler(handleMessage);
  }

  void request({
    required String peer,
    required bool video,
    required int windowMinutes,
  }) {
    final target = peer.trim();
    if (target.isEmpty || _currentUser().isEmpty) {
      _showNotice('Не удалось определить собеседника');
      return;
    }
    if (_callBusy()) {
      _showNotice('Сначала завершите текущий звонок');
      return;
    }
    _send('pulse_request', {
      'to': target,
      'video': video,
      'windowMinutes': windowMinutes,
      'requestId': 'pulse-${_now()}',
    });
    _showNotice(
      video
          ? 'Видеоприглашение FENYVO PULSE отправлено'
          : 'Аудиоприглашение FENYVO PULSE отправлено',
    );
  }

  void accept() {
    final pulse = current;
    if (pulse == null || phase != FenyvoPulsePhase.incoming) return;
    acceptPulse(pulse.id);
  }

  void acceptPulse(String pulseId) {
    final pulse = _pulseById(pulseId);
    if (pulse == null ||
        pulse.to != _currentUser() ||
        pulse.state != 'pending') {
      return;
    }
    _send('pulse_accept', {
      'pulseId': pulse.id,
      'requestId': 'accept-${_now()}',
    });
    _seenIncomingIds.add(pulse.id);
    _upsertPulse(pulse.copyWith(state: 'accepted', acceptedAt: _now()));
    current = _pulseById(pulse.id);
    phase = FenyvoPulsePhase.outgoing;
    _showNotice('Готовность подтверждена. Ищем общий момент…');
    notifyListeners();
  }

  void decline() {
    final pulse = current;
    if (pulse == null) return;
    declinePulse(pulse.id);
  }

  void declinePulse(String pulseId) {
    final pulse = _pulseById(pulseId);
    if (pulse == null || pulse.to != _currentUser()) return;
    _send('pulse_decline', {
      'pulseId': pulse.id,
      'requestId': 'decline-${_now()}',
    });
    _seenIncomingIds.add(pulse.id);
    _removePulse(pulse.id);
  }

  void cancel() {
    final pulse = current;
    if (pulse == null) return;
    cancelPulse(pulse.id);
  }

  void cancelPulse(String pulseId) {
    final pulse = _pulseById(pulseId);
    if (pulse == null) return;
    _send('pulse_cancel', {
      'pulseId': pulse.id,
      'requestId': 'cancel-${_now()}',
    });
    _removePulse(pulse.id);
    _showNotice('FENYVO PULSE отменён');
  }

  void markAllSeen() {
    final before = unreadCount;
    final user = _currentUser();
    _seenIncomingIds.addAll(
      _pulses
          .where((pulse) => pulse.to == user && pulse.state == 'pending')
          .map((pulse) => pulse.id),
    );
    if (before != 0) notifyListeners();
  }

  void sync() {
    if (_currentUser().isNotEmpty) _send('pulse_sync', const {});
  }

  @visibleForTesting
  void handleMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    final rawData = message['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    switch (type) {
      case 'login_success':
        sync();
        break;
      case 'pulse_sync':
        _handleSync(data);
        break;
      case 'pulse_invite':
        final pulse = FenyvoPulse.parse(data['pulse']);
        if (pulse != null) _applyPulse(pulse, incoming: true);
        break;
      case 'pulse_state':
        final pulse = FenyvoPulse.parse(data['pulse']);
        if (pulse != null) _applyPulse(pulse);
        break;
      case 'pulse_match':
        final pulse = FenyvoPulse.parse(data['pulse']);
        if (pulse != null) _applyMatch(pulse);
        break;
      case 'pulse_waiting':
        final pulse = FenyvoPulse.parse(data['pulse']);
        if (pulse != null) _applyPulse(pulse);
        _showNotice(data['reason']?.toString() ?? 'Ждём подходящий момент…');
        break;
      case 'pulse_closed':
        _handleClosed(data);
        break;
      case 'pulse_error':
        _showNotice(data['reason']?.toString() ?? 'Ошибка FENYVO PULSE');
        break;
    }
  }

  void _handleSync(Map<String, dynamic> data) {
    final raw = data['pulses'];
    if (raw is! List || raw.isEmpty) {
      _pulses.clear();
      if (phase != FenyvoPulsePhase.matched) _clear();
      return;
    }
    final user = _currentUser();
    final pulses =
        raw.map(FenyvoPulse.parse).whereType<FenyvoPulse>().toList()
          ..sort((left, right) {
            int priority(FenyvoPulse pulse) {
              if (pulse.state == 'matched') return 0;
              if (pulse.to == user && pulse.state == 'pending') return 1;
              return 2;
            }

            final byPriority = priority(left).compareTo(priority(right));
            return byPriority != 0
                ? byPriority
                : right.createdAt.compareTo(left.createdAt);
          });
    _pulses
      ..clear()
      ..addAll(pulses);
    _seenIncomingIds.removeWhere(
      (id) => !_pulses.any((pulse) => pulse.id == id),
    );
    if (pulses.isEmpty) {
      _clear();
    } else if (pulses.first.state == 'matched') {
      _applyMatch(pulses.first);
    } else {
      _applyPulse(pulses.first);
    }
  }

  void _applyPulse(FenyvoPulse pulse, {bool incoming = false}) {
    _cancelTimers();
    _upsertPulse(pulse);
    current = pulse;
    final user = _currentUser();
    phase = incoming || (pulse.to == user && pulse.state == 'pending')
        ? FenyvoPulsePhase.incoming
        : FenyvoPulsePhase.outgoing;
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_pulses.isNotEmpty) notifyListeners();
    });
    notifyListeners();
  }

  void _applyMatch(FenyvoPulse pulse) {
    if (current?.id == pulse.id && phase == FenyvoPulsePhase.matched) return;
    _cancelTimers();
    _upsertPulse(pulse);
    _seenIncomingIds.add(pulse.id);
    current = pulse;
    phase = FenyvoPulsePhase.matched;
    final startsAt = pulse.startsAt ?? _now() + 4000;
    final delay = Duration(
      milliseconds: (startsAt - _now()).clamp(0, 10000).toInt(),
    );
    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (phase == FenyvoPulsePhase.matched) notifyListeners();
    });
    if (pulse.from == _currentUser()) {
      _startTimer = Timer(delay, () async {
        if (current?.id != pulse.id || phase != FenyvoPulsePhase.matched)
          return;
        if (_callBusy()) {
          cancel();
          _showNotice('Общий момент найден, но линия уже занята');
          return;
        }
        _showNotice('Соединяем с ${pulse.to}…');
        await _startCall(pulse.to, pulse.video);
      });
    }
    notifyListeners();
  }

  void _handleClosed(Map<String, dynamic> data) {
    final id = data['pulseId']?.toString() ?? '';
    final pulse = _pulseById(id);
    if (pulse == null) return;
    final peer = pulse.peerFor(_currentUser());
    final reason = data['reason']?.toString() ?? '';
    _cancelTimers();
    _removePulse(id);
    switch (reason) {
      case 'declined':
        _showNotice('$peer сейчас не готов к звонку');
        break;
      case 'expired':
        _showNotice('Время FENYVO PULSE истекло');
        break;
      case 'cancelled':
        _showNotice('FENYVO PULSE отменён');
        break;
    }
  }

  void _showNotice(String value) {
    notice = value;
    noticeSerial++;
    notifyListeners();
  }

  void _cancelTimers() {
    _startTimer?.cancel();
    _startTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  void _clear() {
    current = null;
    phase = FenyvoPulsePhase.idle;
    notifyListeners();
  }

  FenyvoPulse? _pulseById(String id) {
    for (final pulse in _pulses) {
      if (pulse.id == id) return pulse;
    }
    return null;
  }

  void _upsertPulse(FenyvoPulse pulse) {
    final index = _pulses.indexWhere((item) => item.id == pulse.id);
    if (index == -1) {
      _pulses.add(pulse);
    } else {
      _pulses[index] = pulse;
    }
    _sortPulses();
  }

  void _removePulse(String id) {
    final wasCurrent = current?.id == id;
    _pulses.removeWhere((pulse) => pulse.id == id);
    _seenIncomingIds.remove(id);
    if (wasCurrent) {
      _cancelTimers();
      if (_pulses.isEmpty) {
        _clear();
      } else {
        final next = _pulses.first;
        current = next;
        phase = _phaseFor(next);
        if (phase != FenyvoPulsePhase.matched) {
          _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
            if (_pulses.isNotEmpty) notifyListeners();
          });
        }
        notifyListeners();
      }
    } else {
      notifyListeners();
    }
  }

  FenyvoPulsePhase _phaseFor(FenyvoPulse pulse) {
    if (pulse.state == 'matched') return FenyvoPulsePhase.matched;
    return pulse.to == _currentUser() && pulse.state == 'pending'
        ? FenyvoPulsePhase.incoming
        : FenyvoPulsePhase.outgoing;
  }

  void _sortPulses() {
    final user = _currentUser();
    int priority(FenyvoPulse pulse) {
      if (pulse.state == 'matched') return 0;
      if (pulse.to == user && pulse.state == 'pending') return 1;
      return 2;
    }

    _pulses.sort((left, right) {
      final byPriority = priority(left).compareTo(priority(right));
      return byPriority != 0
          ? byPriority
          : right.createdAt.compareTo(left.createdAt);
    });
  }

  @override
  void dispose() {
    _cancelTimers();
    if (_initialized) {
      SocketService.instance.removeMessageHandler(handleMessage);
    }
    super.dispose();
  }
}
