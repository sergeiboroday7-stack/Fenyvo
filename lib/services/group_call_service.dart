import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'app_visibility.dart';
import 'call_service.dart';
import 'group_call_state.dart';
import 'incoming_call_alert_service.dart';
import 'socket_service.dart';
import 'turn_credential_service.dart';

enum GroupCallPhase { idle, invited, joining, active, leaving }

enum GroupCallLayout { stage, grid, spotlight }

class _GroupPeer {
  _GroupPeer(this.member, this.connection);
  final GroupCallMember member;
  final RTCPeerConnection connection;
  final List<Map<String, dynamic>> localIce = [], remoteIce = [];
  bool localSet = false, remoteSet = false;
  bool ready = false;
  String status = 'Подключение…';
  Timer? timeout;
}

class GroupCallService extends ChangeNotifier {
  GroupCallService._()
    : _send = SocketService.instance.sendGroupCall,
      _user = (() => SocketService.instance.currentUser ?? ''),
      _authenticated = (() => SocketService.instance.isAuthenticated),
      _privateBusy = (() => CallService.instance.hasCall),
      _foreground = (() => AppVisibility.instance.foreground),
      _renderLocalVideo = true,
      _media = ((withVideo) => navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': withVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 20, 'max': 24},
              }
            : false,
      })),
      _connection = (() => createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': TurnCredentialService.iceServers,
      }));

  @visibleForTesting
  GroupCallService.forTesting({
    required void Function(String, Map<String, dynamic>) send,
    required String user,
    required Future<MediaStream> Function() media,
    required Future<RTCPeerConnection> Function() connection,
  }) : _send = send,
       _user = (() => user),
       _authenticated = (() => true),
       _privateBusy = (() => false),
       _foreground = (() => false),
       _renderLocalVideo = false,
       _media = ((_) => media()),
       _connection = connection;

  static final instance = GroupCallService._();
  final void Function(String, Map<String, dynamic>) _send;
  final String Function() _user;
  final bool Function() _authenticated, _privateBusy, _foreground;
  final bool _renderLocalVideo;
  final Future<MediaStream> Function(bool withVideo) _media;
  final Future<RTCPeerConnection> Function() _connection;
  final Map<String, GroupCallState> rooms = {};
  final Map<String, _GroupPeer> _peers = {};
  final Map<String, int> _peerReconnectAttempts = {};
  final Map<String, List<Map<String, dynamic>>> _pendingSignals = {};
  final Map<String, RTCVideoRenderer> remoteVideos = {};
  final Map<String, MediaStream> _fallbackRemoteStreams = {};
  RTCVideoRenderer? localVideo;
  final Set<String> _dismissed = {};
  final Set<String> _expectedLeftSessions = {};
  Future<void> _events = Future.value();
  Future<void>? _leaving;
  MediaStream? _stream;
  Timer? _waitTimer, _heartbeat, _clockTimer, _controlsTimer, _pendingJoinTimer;
  Timer? _speakingTimer;
  bool _speakingPollBusy = false;
  DateTime? _lastSpeakingAt;
  final Stopwatch _clock = Stopwatch();
  int _epoch = 0;
  bool _initialized = false, _speakerChanging = false;
  bool _transitioningViewerToStage = false;
  String? _transitionGroupId;
  String? _requestId;
  String? _pendingJoinGroupId;
  String? _pendingJoinCallId;
  String? _pendingJoinName;
  bool _pendingJoinVideo = true;
  String? _reconnectGroupId;
  String? _reconnectCallId;
  String? _reconnectName;
  bool _reconnectVideo = true;
  bool _reconnectWasViewer = false;
  bool _reconnectWasOwner = false;
  bool _reconnectWasModerator = false;
  bool _reconnectAttemptStarted = false;
  String? sessionId;
  String? groupId;
  GroupCallState? current;
  String groupName = 'Групповой звонок';
  GroupCallPhase phase = GroupCallPhase.idle;
  bool supported = false, microphoneEnabled = true, speakerphoneEnabled = false;
  bool videoEnabled = true;
  String? speakingUser;
  GroupCallLayout layout = GroupCallLayout.stage;
  String? featuredUser;
  bool controlsVisible = true;
  String? notice;
  int noticeSerial = 0;
  bool get hasCall => phase != GroupCallPhase.idle;
  bool get _hasReconnectIntent =>
      _reconnectGroupId != null && _reconnectCallId != null;
  bool get isViewer => current?.member(user)?.isViewer == true;
  bool isJoinPending(String id) => _pendingJoinGroupId == id;
  String get user => _user();
  Duration get elapsed => _clock.elapsed;
  bool get canSwitchSpeaker =>
      _stream != null && (Platform.isAndroid || Platform.isIOS);
  String peerStatus(String user) => _peers[user]?.status ?? 'Подключение…';
  int get connectedCount =>
      _peers.values.where((p) => p.status == 'В сети').length;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    SocketService.instance.addMessageHandler(_onMessage);
    AppVisibility.instance.changes.addListener(_handleVisibilityChange);
    if (_authenticated()) _send('group_call_sync', {});
  }

  void _handleVisibilityChange() {
    if (phase != GroupCallPhase.active ||
        current == null ||
        sessionId == null) {
      return;
    }
    _send('group_call_presence', {
      ..._lease,
      'away': !AppVisibility.instance.foreground,
    });
  }

  void requestState(String id) {
    if (_authenticated()) _send('group_call_get', {'groupId': id});
  }

  void requestJoin(
    String id,
    String name,
    String callId, {
    bool withVideo = true,
  }) {
    if (!_authenticated() ||
        (hasCall && !isViewer && !_hasReconnectIntent) ||
        _privateBusy()) {
      _notifyError('Сначала завершите текущий звонок');
      return;
    }
    _pendingJoinTimer?.cancel();
    _pendingJoinGroupId = id;
    _pendingJoinCallId = callId;
    _pendingJoinName = name;
    _pendingJoinVideo = withVideo;

    _send('group_call_join_request', {
      'groupId': id,
      'callId': callId,
      'videoEnabled': withVideo,
    });

    _pendingJoinTimer = Timer(const Duration(seconds: 45), () {
      if (_pendingJoinGroupId != id || _pendingJoinCallId != callId) {
        return;
      }
      _clearPendingJoin();
      const message =
          'Время ожидания ответа истекло. Можно отправить запрос снова.';
      if (_hasReconnectIntent) {
        _cancelReconnect(message);
      } else {
        _notifyError(message);
      }
    });

    notifyListeners();
  }

  Future<void> watch(String id, String name, String callId) async {
    if (!_authenticated() ||
        (hasCall && !_hasReconnectIntent) ||
        _privateBusy()) {
      _notifyError('Сначала завершите текущий звонок');
      return;
    }
    _waitTimer?.cancel();
    final epoch = ++_epoch;
    phase = GroupCallPhase.joining;
    groupId = id;
    groupName = name;
    current = rooms[id];
    sessionId = null;
    microphoneEnabled = false;
    videoEnabled = false;
    _requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    notifyListeners();
    _send('group_call_watch', {
      'groupId': id,
      'callId': callId,
      'requestId': _requestId,
    });
    _waitTimer = Timer(const Duration(seconds: 15), () {
      if (epoch == _epoch && phase == GroupCallPhase.joining) {
        unawaited(leave(message: 'Не удалось открыть трансляцию'));
      }
    });
  }

  void respondToJoinRequest(String username, {required bool accepted}) {
    final room = current;
    if (room == null || phase != GroupCallPhase.active) return;
    _send('group_call_join_response', {
      ..._lease,
      'target': username,
      'accepted': accepted,
    });
  }

  void _clearPendingJoin() {
    _pendingJoinTimer?.cancel();
    _pendingJoinTimer = null;
    _pendingJoinGroupId = null;
    _pendingJoinCallId = null;
    _pendingJoinName = null;
    _pendingJoinVideo = true;
  }

  void _clearReconnectIntent() {
    _reconnectGroupId = null;
    _reconnectCallId = null;
    _reconnectName = null;
    _reconnectVideo = true;
    _reconnectWasViewer = false;
    _reconnectWasOwner = false;
    _reconnectWasModerator = false;
    _reconnectAttemptStarted = false;
  }

  void _cancelReconnect(String message) {
    _clearReconnectIntent();
    current = null;
    groupId = null;
    sessionId = null;
    _requestId = null;
    phase = GroupCallPhase.idle;
    notifyListeners();
    _notifyError(message);
  }

  Future<void> _suspendForReconnect() async {
    ++_epoch;
    _clearPendingJoin();
    _waitTimer?.cancel();
    _heartbeat?.cancel();
    _clockTimer?.cancel();
    _stopSpeakingMonitor();
    _controlsTimer?.cancel();
    _clock.stop();

    final peers = _peers.values.toList();
    _peers.clear();
    _peerReconnectAttempts.clear();
    _pendingSignals.clear();

    final stream = _stream;
    _stream = null;

    try {
      await IncomingCallAlertService.instance.stop().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}

    for (final peer in peers) {
      await _releasePeer(peer).timeout(const Duration(seconds: 3));
    }

    for (final renderer in remoteVideos.values) {
      try {
        renderer.srcObject = null;
        await renderer.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    remoteVideos.clear();

    if (stream != null) {
      await _releaseStream(stream);
    }

    if (_renderLocalVideo && localVideo != null) {
      try {
        localVideo!.srcObject = null;
        await localVideo!.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
      localVideo = null;
    }

    if (stream != null && Platform.isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice().timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
    }

    sessionId = null;
    _requestId = null;
    _expectedLeftSessions.clear();
    phase = GroupCallPhase.joining;
    notifyListeners();
  }

  void _notifyError(String message) {
    notice = message;
    noticeSerial++;
    notifyListeners();
  }

  Future<void> begin(
    String id,
    String name, {
    String? existingCallId,
    bool withVideo = true,
  }) async {
    if (!supported) {
      _notifyError(
        'Для групповых звонков нужно перезапустить обновлённый сервер.',
      );
      return;
    }
    if (!_authenticated()) {
      _notifyError('Нет связи с сервером');
      return;
    }
    if (_privateBusy() ||
        (hasCall &&
            phase != GroupCallPhase.invited &&
            !_transitioningViewerToStage &&
            !_hasReconnectIntent)) {
      _notifyError('Сначала завершите текущий звонок');
      return;
    }
    _waitTimer?.cancel();
    final epoch = ++_epoch;
    phase = GroupCallPhase.joining;
    groupId = id;
    groupName = name;
    sessionId = null;
    current = rooms[id];
    _requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    microphoneEnabled = true;
    videoEnabled = withVideo;
    layout = GroupCallLayout.stage;
    featuredUser = null;
    speakerphoneEnabled = withVideo;
    _clock.reset();
    notifyListeners();
    _waitTimer = Timer(const Duration(seconds: 20), () {
      if (epoch == _epoch && phase == GroupCallPhase.joining) {
        unawaited(leave(message: 'Не удалось подключить камеру или микрофон.'));
      }
    });
    try {
      try {
        await IncomingCallAlertService.instance.stop().timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
      if (epoch != _epoch) return;
      if (Platform.isAndroid)
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      if (epoch != _epoch) return;
      MediaStream stream;
      try {
        stream = await _media(withVideo).timeout(const Duration(seconds: 12));
      } catch (_) {
        if (!withVideo) rethrow;
        stream = await _media(false).timeout(const Duration(seconds: 12));
        videoEnabled = false;
        _notifyError('Камера недоступна — вход выполнен только со звуком');
      }
      if (epoch != _epoch) {
        await _releaseStream(stream);
        return;
      }
      _stream = stream;
      if (_renderLocalVideo && stream.getVideoTracks().isNotEmpty) {
        try {
          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;
          localVideo = renderer;
        } catch (_) {
          debugPrint('Group call local video preview is unavailable');
        }
      }
      if (canSwitchSpeaker) await Helper.setSpeakerphoneOn(speakerphoneEnabled);
      if (epoch != _epoch) return;
      _send(existingCallId == null ? 'group_call_start' : 'group_call_join', {
        'groupId': id,
        'callId': existingCallId,
        'requestId': _requestId,
        'videoEnabled': videoEnabled,
      });
      _waitTimer?.cancel();
      _waitTimer = Timer(const Duration(seconds: 15), () {
        if (epoch == _epoch && phase == GroupCallPhase.joining) {
          unawaited(
            leave(message: 'Сервер не ответил. Проверьте, что он обновлён.'),
          );
        }
      });
    } catch (_) {
      if (epoch == _epoch)
        await leave(
          message: 'Не удалось подключить микрофон. Проверьте разрешение и закройте другие звонки.',
        );
    }
  }

  Future<void> accept({bool withVideo = true}) async {
    final room = current;
    if (phase == GroupCallPhase.invited && room != null) {
      await begin(
        room.groupId,
        room.name,
        existingCallId: room.id,
        withVideo: withVideo,
      );
    }
  }

  Map<String, dynamic> get _lease => {
    'groupId': groupId,
    'callId': current?.id,
    'sessionId': sessionId,
  };

  void setMicrophoneEnabled(bool enabled) {
    if (_stream == null || phase != GroupCallPhase.active) return;
    if (microphoneEnabled == enabled) return;

    microphoneEnabled = enabled;
    for (final track in _stream!.getAudioTracks()) {
      track.enabled = enabled;
    }

    _send('group_call_mute', {..._lease, 'muted': !enabled});
    notifyListeners();
  }

  void toggleMicrophone() {
    setMicrophoneEnabled(!microphoneEnabled);
  }

  Future<void> switchCamera() async {
    if (_stream == null || phase != GroupCallPhase.active) return;

    final tracks = _stream!.getVideoTracks();
    if (tracks.isEmpty) {
      _notifyError('Камера недоступна');
      return;
    }

    try {
      await Helper.switchCamera(tracks.first);
      notifyListeners();
    } catch (_) {
      _notifyError('Не удалось переключить камеру');
    }
  }

  void toggleVideo() {
    if (_stream == null || phase != GroupCallPhase.active) return;
    final tracks = _stream!.getVideoTracks();
    if (tracks.isEmpty) {
      _notifyError('Камера недоступна. Войдите в звонок повторно с камерой.');
      return;
    }
    videoEnabled = !videoEnabled;
    for (final track in tracks) {
      track.enabled = videoEnabled;
    }
    _send('group_call_video', {..._lease, 'videoEnabled': videoEnabled});
    notifyListeners();
  }

  bool get isHost => current?.startedBy == user;
  bool get isOwner => current?.owner == user;
  bool get isModerator => current?.member(user)?.isModerator == true;

  void setLayout(GroupCallLayout value) {
    layout = value;
    notifyListeners();
  }

  void toggleControls() {
    controlsVisible = !controlsVisible;
    _controlsTimer?.cancel();
    if (controlsVisible) _armControlsTimer();
    notifyListeners();
  }

  void revealControls() {
    controlsVisible = true;
    _armControlsTimer();
    notifyListeners();
  }

  void _armControlsTimer() {
    _controlsTimer?.cancel();
    if (phase != GroupCallPhase.active) return;
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (phase == GroupCallPhase.active) {
        controlsVisible = false;
        notifyListeners();
      }
    });
  }

  bool get canManageBroadcast => isHost || isModerator;

  void feature(String username) {
    final member = current?.member(username);
    if (phase != GroupCallPhase.active ||
        !canManageBroadcast ||
        member == null ||
        member.isViewer) {
      return;
    }
    featuredUser = username;
    layout = GroupCallLayout.spotlight;
    _send('group_call_feature', {..._lease, 'target': username});
    notifyListeners();
  }

  bool canModerate(GroupCallMember member) {
    if (member.user == user || member.isHost) return false;
    if (isHost) return true;
    return isModerator && !member.isModerator;
  }

  void moderate(String target, String action) {
    final member = current?.member(target);
    if (member == null ||
        !canModerate(member) ||
        phase != GroupCallPhase.active)
      return;
    _send('group_call_moderate', {
      ..._lease,
      'target': target,
      'action': action,
    });
  }

  void takeHostRole() {
    if (phase != GroupCallPhase.active ||
        current?.isWaitingForHost != true ||
        !isModerator) {
      return;
    }
    _send('group_call_take_host', _lease);
  }

  void pinMessage(Map<String, dynamic>? message) {
    if (phase != GroupCallPhase.active ||
        current == null ||
        !canManageBroadcast) {
      return;
    }
    _send('group_call_pin', {..._lease, 'message': message});
  }

  Future<void> toggleSpeaker() async {
    if (!canSwitchSpeaker || _speakerChanging) return;

    final epoch = _epoch;
    final next = !speakerphoneEnabled;
    _speakerChanging = true;

    try {
      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );

        if (epoch != _epoch) return;

        await Future<void>.delayed(const Duration(milliseconds: 80));

        if (epoch != _epoch) return;
      }

      await Helper.setSpeakerphoneOn(next);

      if (epoch == _epoch) {
        speakerphoneEnabled = next;
        notifyListeners();
      }
    } catch (_) {
      if (epoch == _epoch) {
        _notifyError('Не удалось переключить динамик');
      }
    } finally {
      _speakerChanging = false;
    }
  }

  void _onMessage(Map<String, dynamic> packet) {
    unawaited(handlePacket(packet));
  }

  @visibleForTesting
  Future<void> handlePacket(Map<String, dynamic> packet) {
    _events = _events.then((_) => _handle(packet)).catchError((Object error) {
      debugPrint('GROUP_CALL_PACKET_ERROR: $error');
      if (hasCall)
        unawaited(
          leave(
            message: 'Не удалось установить групповой звонок. Попробуйте войти снова.',
          ),
        );
    });
    return _events;
  }

  Future<void> _handle(Map<String, dynamic> packet) async {
    final type = packet['type'];
    final data = packet['data'] is Map
        ? Map<String, dynamic>.from(packet['data'])
        : <String, dynamic>{};
    if (type == 'login_success') {
      supported = false;
      rooms.clear();
      _clearPendingJoin();
      _reconnectAttemptStarted = false;
      _send('group_call_sync', {});
      return;
    }
    if (type == 'disconnected') {
      supported = false;

      if (hasCall && current != null) {
        final room = current!;
        final member = room.member(user);

        _reconnectGroupId = room.groupId;
        _reconnectCallId = room.id;
        _reconnectName = groupName;
        _reconnectVideo = videoEnabled;
        _reconnectWasViewer = member?.isViewer == true;
        _reconnectWasOwner = room.owner == user;
        _reconnectWasModerator = member?.isModerator == true;
        _reconnectAttemptStarted = false;

        await _suspendForReconnect();
      }

      rooms.clear();
      _clearPendingJoin();
      notifyListeners();
      return;
    }
    if (type == 'group_call_sync') {
      supported = true;
      rooms.clear();

      for (final item in data['calls'] is List ? data['calls'] : []) {
        final room = GroupCallState.parse(item);
        if (room != null) rooms[room.groupId] = room;
      }

      final reconnectGroup = _reconnectGroupId;
      final reconnectCall = _reconnectCallId;
      final reconnectName = _reconnectName;

      if (reconnectGroup != null &&
          reconnectCall != null &&
          reconnectName != null &&
          !_reconnectAttemptStarted) {
        final room = rooms[reconnectGroup];

        if (room == null || room.id != reconnectCall) {
          _cancelReconnect('Групповой звонок уже завершён');
          return;
        }

        _reconnectAttemptStarted = true;

        if (_reconnectWasViewer) {
          await watch(reconnectGroup, reconnectName, reconnectCall);
          return;
        }

        if (_reconnectWasOwner ||
            (_reconnectWasModerator && room.awaitingHost)) {
          await begin(
            reconnectGroup,
            reconnectName,
            existingCallId: reconnectCall,
            withVideo: _reconnectVideo,
          );
          return;
        }

        requestJoin(
          reconnectGroup,
          reconnectName,
          reconnectCall,
          withVideo: _reconnectVideo,
        );
        return;
      }

      notifyListeners();
      return;
    }
    if (type == 'group_call_join_request_status') {
      if (data['pending'] == true) {
        _notifyError('Запрос отправлен ведущему');
      }
      return;
    }
    if (type == 'group_call_join_response') {
      final accepted = data['accepted'] == true;
      final requestedGroup = _pendingJoinGroupId;
      final requestedCall = _pendingJoinCallId;
      final requestedName = _pendingJoinName;
      final requestedVideo = _pendingJoinVideo;

      if (requestedGroup == null ||
          requestedCall == null ||
          requestedName == null) {
        return;
      }

      _clearPendingJoin();
      notifyListeners();
      if (!accepted) {
        final reason = data['reason']?.toString() ?? 'Вход не разрешён';
        if (_hasReconnectIntent) {
          _cancelReconnect(reason);
        } else {
          _notifyError(reason);
        }
        return;
      }
      if (isViewer) {
        _transitioningViewerToStage = true;
        _transitionGroupId = requestedGroup;
        await _leaveViewerForStage();
      }
      await begin(
        requestedGroup,
        requestedName,
        existingCallId: requestedCall,
        withVideo: requestedVideo,
      );
      return;
    }
    if (type == 'group_call_state') {
      supported = true;
      final id = data['groupId']?.toString() ?? '';
      final room = GroupCallState.parse(data['call']);
      if (room == null) {
        rooms.remove(id);
      } else {
        rooms[id] = room;
      }
      if (_transitioningViewerToStage && _transitionGroupId == id) {
        final transitionedMember = room?.member(user);
        if (sessionId == null || transitionedMember?.sessionId != sessionId) {
          // The server broadcasts the viewer removal before it processes the
          // stage join. Message handlers may overlap, so that older snapshot
          // can finish after group_call_joined and must not evict the new
          // stage session.
          notifyListeners();
          return;
        }
        _transitioningViewerToStage = false;
        _transitionGroupId = null;
      }
      if (groupId == id &&
          current != null &&
          room?.id != current!.id &&
          hasCall) {
        await leave(message: 'Групповой звонок завершён');
      } else if (groupId == id &&
          room != null &&
          phase == GroupCallPhase.active) {
        await _applyState(room);
      } else if (groupId == id && phase == GroupCallPhase.invited) {
        current = room;
      }
      notifyListeners();
      return;
    }
    if (type == 'group_call_invite') {
      final room = GroupCallState.parse(data['call']);
      if (room == null) return;
      rooms[room.groupId] = room;
      if (!_foreground() ||
          hasCall ||
          _privateBusy() ||
          _dismissed.contains(room.id) ||
          room.startedBy == user)
        return;
      supported = true;
      current = room;
      groupId = room.groupId;
      groupName = room.name;
      phase = GroupCallPhase.invited;
      ++_epoch;
      notifyListeners();
      await IncomingCallAlertService.instance.start(room.id);
      _waitTimer = Timer(const Duration(seconds: 45), () {
        if (phase == GroupCallPhase.invited && current?.id == room.id)
          unawaited(leave());
      });
      return;
    }
    if (type == 'group_call_joined' || type == 'group_call_watching') {
      final room = GroupCallState.parse(data['call']);
      final lease = data['sessionId']?.toString();
      if (room == null ||
          lease == null ||
          room.member(user)?.sessionId != lease)
        return;
      if (phase != GroupCallPhase.joining || data['requestId'] != _requestId) {
        if (lease != sessionId)
          _send('group_call_leave', {
            'groupId': room.groupId,
            'callId': room.id,
            'sessionId': lease,
          });
        return;
      }
      _waitTimer?.cancel();
      sessionId = lease;
      current = room;
      phase = GroupCallPhase.active;
      _clearReconnectIntent();
      controlsVisible = true;
      _armControlsTimer();
      final epoch = _epoch;
      _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        if (epoch == _epoch) _send('group_call_heartbeat', _lease);
      });
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (epoch == _epoch) notifyListeners();
      });
      _startSpeakingMonitor(epoch);
      await _applyState(room);
      notifyListeners();
      return;
    }
    if (type == 'group_call_left' &&
        _expectedLeftSessions.remove(data['sessionId']?.toString() ?? '')) {
      return;
    }
    if (type == 'group_call_left' &&
        data['callId'] == current?.id &&
        data['sessionId'] == sessionId &&
        sessionId != null) {
      await leave(message: data['reason']?.toString());
      return;
    }
    if (type == 'group_call_error') {
      _transitioningViewerToStage = false;
      _transitionGroupId = null;
      final reason = data['reason']?.toString() ?? 'Ошибка группового звонка';
      if ((_requestId != null && data['requestId'] == _requestId) ||
          (current != null &&
              data['callId'] == current!.id &&
              phase == GroupCallPhase.active)) {
        await leave(message: reason);
      } else {
        _notifyError(reason);
      }
      return;
    }
    if (type == 'group_call_signal' &&
        phase == GroupCallPhase.active &&
        data['callId'] == current?.id &&
        data['toSession'] == sessionId) {
      final peer = _peers[data['from']];
      if (peer == null || !peer.ready) {
        final from = data['from']?.toString() ?? '';
        if (from.isNotEmpty && data['signal'] is Map) {
          final queue = _pendingSignals.putIfAbsent(from, () => []);
          if (queue.length < 256) queue.add(Map<String, dynamic>.from(data));
        }
        return;
      }
      await _handlePeerSignal(peer, data);
    }
    if (type == 'group_call_moderation' &&
        phase == GroupCallPhase.active &&
        data['callId'] == current?.id) {
      final action = data['action']?.toString();
      if (action == 'mute') {
        microphoneEnabled = false;
        for (final track in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
          track.enabled = false;
        }
      } else if (action == 'video_off') {
        videoEnabled = false;
        for (final track in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
          track.enabled = false;
        }
      }
      _notifyError('Ведущий изменил ваши настройки звонка');
    }
  }

  Future<void> _handlePeerSignal(
    _GroupPeer peer,
    Map<String, dynamic> data,
  ) async {
    if (data['fromSession'] != peer.member.sessionId ||
        data['signal'] is! Map) {
      return;
    }
    final signal = Map<String, dynamic>.from(data['signal']);
    final epoch = _epoch;
    bool valid() =>
        epoch == _epoch && identical(_peers[peer.member.user], peer);
    if (signal['kind'] == 'ice') {
      if (signal['candidate'] is! Map) return;
      final candidate = Map<String, dynamic>.from(signal['candidate']);
      if (!peer.remoteSet) {
        if (peer.remoteIce.length < 256) peer.remoteIce.add(candidate);
      } else {
        await _addIce(peer, candidate);
      }
      return;
    }
    if (signal['kind'] != 'offer' && signal['kind'] != 'answer') return;
    final offer = signal['kind'] == 'offer';
    final localMember = current?.member(user);
    final localMakesOffer = localMember?.isViewer == true
        ? false
        : peer.member.isViewer
        ? true
        : GroupCallState.makesOffer(sessionId!, peer.member.sessionId);
    if (peer.remoteSet || offer == localMakesOffer) {
      return;
    }
    await peer.connection.setRemoteDescription(
      RTCSessionDescription(
        signal['sdp']?.toString(),
        offer ? 'offer' : 'answer',
      ),
    );
    if (!valid()) return;
    peer.remoteSet = true;
    for (final candidate in peer.remoteIce) {
      if (valid()) await _addIce(peer, candidate);
    }
    peer.remoteIce.clear();
    if (offer && valid()) {
      final answer = await peer.connection.createAnswer();
      if (!valid()) return;
      await peer.connection.setLocalDescription(answer);
      if (valid()) _sendDescription(peer, answer);
    }
  }

  Future<void> _applyState(GroupCallState room) async {
    final epoch = _epoch;
    if (room.member(user)?.sessionId != sessionId) {
      debugPrint('GROUP_CALL_STALE_STATE_IGNORED');
      return;
    }
    current = room;
    rooms[room.groupId] = room;
    if (room.featuredUser.isNotEmpty) {
      featuredUser = room.featuredUser;
      layout = GroupCallLayout.spotlight;
    }
    for (final peer in _peers.values.toList()) {
      if (room.member(peer.member.user)?.sessionId != peer.member.sessionId) {
        _peers.remove(peer.member.user);
        await _releasePeer(peer).timeout(const Duration(seconds: 3));
      }
    }
    for (final member in room.members) {
      if (epoch != _epoch) return;
      if (member.user == user || _peers.containsKey(member.user)) continue;
      final localMember = room.member(user);
      if (localMember?.isViewer == true && member.isViewer) continue;
      final pc = await _connection();
      if (epoch != _epoch) {
        await pc.close();
        await pc.dispose();
        return;
      }
      final peer = _GroupPeer(member, pc);
      _peers[member.user] = peer;
      bool valid() => epoch == _epoch && identical(_peers[member.user], peer);
      pc.onIceCandidate = (c) {
        if (!valid() || c.candidate?.isNotEmpty != true) return;
        final candidate = <String, dynamic>{
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        };
        if (peer.localSet)
          _signal(peer, {'kind': 'ice', 'candidate': candidate});
        else if (peer.localIce.length < 256)
          peer.localIce.add(candidate);
      };
      pc.onAddStream = (stream) {
        if (!valid() || Platform.isAndroid) return;
        unawaited(_attachRemoteVideo(peer.member.user, stream));
      };

      pc.onTrack = (event) {
        if (!valid()) return;

        if (event.track.kind == 'audio') {
          event.track.enabled = true;
        }

        if (event.track.kind == 'video') {
          unawaited(() async {
            if (!valid()) return;

            if (event.streams.isEmpty && Platform.isAndroid) {
              debugPrint(
                'Group call Android video track arrived without a MediaStream',
              );
              return;
            }

            MediaStream? stream = event.streams.isNotEmpty
                ? event.streams.first
                : _fallbackRemoteStreams[peer.member.user];

            if (stream == null) {
              try {
                stream = await createLocalMediaStream(
                  'spartan_group_remote_${peer.member.user}',
                );
              } catch (error) {
                debugPrint(
                  'Group call remote media stream could not be created: $error',
                );
                return;
              }

              if (!valid()) {
                try {
                  await stream.dispose();
                } catch (_) {}
                return;
              }

              _fallbackRemoteStreams[peer.member.user] = stream;
            }

            final remoteStream = stream;

            if (event.streams.isEmpty &&
                !remoteStream.getTracks().any(
                  (track) => track.id == event.track.id,
                )) {
              try {
                await remoteStream.addTrack(event.track);
              } catch (error) {
                debugPrint(
                  'Group call remote video track could not be attached: $error',
                );
                return;
              }
            }

            if (!valid()) return;

            event.track.enabled = true;
            await _attachRemoteVideo(peer.member.user, remoteStream);
          }());
        }
      };
      pc.onConnectionState = (state) {
        if (!valid()) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          peer.timeout?.cancel();
          _peerReconnectAttempts[peer.member.user] = 0;
          peer.status = 'В сети';
          _clock.start();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          peer.status = 'Связь прервалась';
          _schedulePeerReconnect(peer);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          peer.status = 'Переподключение…';
          _schedulePeerReconnect(peer, immediate: true);
        }
        notifyListeners();
      };
      peer.timeout = Timer(const Duration(seconds: 35), () {
        if (valid() && peer.status != 'В сети') {
          peer.status = 'Переподключение…';
          _schedulePeerReconnect(peer, immediate: true);
        }
      });
      final stream = _stream;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          if (!valid()) return;
          await pc.addTrack(track, stream);
        }
      }
      Future<void> drainPendingSignals() async {
        while (valid()) {
          final pending = _pendingSignals.remove(member.user);
          if (pending == null || pending.isEmpty) return;

          for (final packet in pending) {
            if (!valid()) return;
            await _handlePeerSignal(peer, packet);
          }
        }
      }

      await drainPendingSignals();

      final shouldOffer = localMember?.isViewer == true
          ? false
          : member.isViewer
          ? true
          : GroupCallState.makesOffer(sessionId!, member.sessionId);

      if (valid() && shouldOffer) {
        final offer = await pc.createOffer();
        if (!valid()) return;
        await pc.setLocalDescription(offer);
        if (valid()) _sendDescription(peer, offer);
      }

      await drainPendingSignals();

      if (valid()) {
        peer.ready = true;
      }
    }
  }

  void _startSpeakingMonitor(int epoch) {
    _stopSpeakingMonitor();

    _speakingTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (epoch != _epoch || phase != GroupCallPhase.active) return;
      unawaited(_pollSpeaking(epoch));
    });
  }

  void _stopSpeakingMonitor() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _speakingPollBusy = false;
    _lastSpeakingAt = null;

    if (speakingUser != null) {
      speakingUser = null;
      notifyListeners();
    }
  }

  Future<void> _pollSpeaking(int epoch) async {
    if (_speakingPollBusy ||
        epoch != _epoch ||
        phase != GroupCallPhase.active) {
      return;
    }

    _speakingPollBusy = true;

    try {
      String? loudestUser;
      double loudestLevel = 0.0;
      double localLevel = 0.0;

      for (final entry in _peers.entries.toList()) {
        if (epoch != _epoch || phase != GroupCallPhase.active) return;

        try {
          final reports = await entry.value.connection.getStats();

          if (epoch != _epoch || phase != GroupCallPhase.active) return;

          for (final report in reports) {
            final values = report.values;

            final kind = '${values['kind'] ?? values['mediaType'] ?? ''}'
                .toLowerCase();

            if (kind != 'audio') continue;

            final raw = values['audioLevel'];

            final level = raw is num
                ? raw.toDouble()
                : double.tryParse('$raw') ?? 0.0;

            if (level <= 0) continue;

            if (report.type == 'inbound-rtp') {
              if (level > loudestLevel) {
                loudestLevel = level;
                loudestUser = entry.key;
              }
            } else if (report.type == 'media-source') {
              if (level > localLevel) {
                localLevel = level;
              }
            }
          }
        } catch (_) {}
      }

      if (epoch != _epoch || phase != GroupCallPhase.active) return;

      if (localLevel > loudestLevel) {
        loudestLevel = localLevel;
        loudestUser = user;
      }

      const speakingThreshold = 0.015;

      if (loudestUser != null && loudestLevel >= speakingThreshold) {
        _lastSpeakingAt = DateTime.now();

        if (speakingUser != loudestUser) {
          speakingUser = loudestUser;
          notifyListeners();
        }

        return;
      }

      final last = _lastSpeakingAt;

      if (speakingUser != null &&
          (last == null ||
              DateTime.now().difference(last) >
                  const Duration(milliseconds: 700))) {
        speakingUser = null;
        notifyListeners();
      }
    } finally {
      _speakingPollBusy = false;
    }
  }

  void _schedulePeerReconnect(_GroupPeer peer, {bool immediate = false}) {
    if (!identical(_peers[peer.member.user], peer)) return;
    final attempts = _peerReconnectAttempts[peer.member.user] ?? 0;
    if (attempts >= 2) {
      peer.status = 'Нет связи — войдите снова';
      notifyListeners();
      return;
    }
    peer.timeout?.cancel();
    peer.timeout = Timer(
      immediate ? Duration.zero : const Duration(seconds: 4),
      () {
        if (!identical(_peers[peer.member.user], peer)) return;
        unawaited(_restartPeer(peer));
      },
    );
  }

  Future<void> _restartPeer(_GroupPeer peer) async {
    if (!identical(_peers[peer.member.user], peer)) return;
    final username = peer.member.user;
    _peerReconnectAttempts[username] =
        (_peerReconnectAttempts[username] ?? 0) + 1;
    _peers.remove(username);
    await _releasePeer(peer).timeout(const Duration(seconds: 3));
    final room = current;
    if (room != null && phase == GroupCallPhase.active) {
      await _applyState(room);
    }
  }

  void inviteViewer(String username) {
    final room = current;
    final target = username.trim();
    if (room == null || phase != GroupCallPhase.active || target.isEmpty)
      return;
    if (!isHost && !isModerator) {
      _notifyError('Приглашать на сцену может ведущий или модератор');
      return;
    }
    _send('group_call_stage_invite', {..._lease, 'target': target});
  }

  Future<void> acceptStageInvite({bool withVideo = true}) async {
    final room = current;
    if (room == null || !isViewer) return;
    final id = room.groupId;
    final name = room.name;
    final callId = room.id;
    _transitioningViewerToStage = true;
    _transitionGroupId = id;
    await _leaveViewerForStage();
    await begin(id, name, existingCallId: callId, withVideo: withVideo);
  }

  Future<void> returnToStage({bool withVideo = true}) async {
    final room = current;
    if (room == null ||
        phase != GroupCallPhase.active ||
        !isViewer ||
        room.isWaitingForHost != true ||
        (!isOwner && !isModerator)) {
      return;
    }

    final id = room.groupId;
    final name = room.name;
    final callId = room.id;
    _transitioningViewerToStage = true;
    _transitionGroupId = id;
    await _leaveViewerForStage();
    await begin(id, name, existingCallId: callId, withVideo: withVideo);
  }

  void declineStageInvite() {
    if (current == null || !isViewer) return;
    _send('group_call_stage_invite_response', {..._lease, 'accepted': false});
  }

  Future<void> _leaveViewerForStage() async {
    final room = current;
    final lease = Map<String, dynamic>.from(_lease);
    ++_epoch;
    _waitTimer?.cancel();
    _heartbeat?.cancel();
    _clockTimer?.cancel();
    _stopSpeakingMonitor();
    _controlsTimer?.cancel();
    if (room != null && sessionId != null) {
      _expectedLeftSessions.add(sessionId!);
      _send('group_call_unwatch', {...lease, 'forStage': true});
    }
    final peers = _peers.values.toList();
    _peers.clear();
    _peerReconnectAttempts.clear();
    _pendingSignals.clear();
    for (final peer in peers) {
      await _releasePeer(peer).timeout(const Duration(seconds: 3));
    }
    for (final renderer in remoteVideos.values) {
      try {
        renderer.srcObject = null;
        await renderer.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    remoteVideos.clear();
    sessionId = null;
    current = null;
    groupId = null;
    _requestId = null;
    phase = _transitioningViewerToStage
        ? GroupCallPhase.joining
        : GroupCallPhase.idle;
    notifyListeners();
  }

  Future<void> _attachRemoteVideo(String user, MediaStream stream) async {
    final renderer = remoteVideos[user] ??= RTCVideoRenderer();
    if (renderer.textureId == null) await renderer.initialize();
    renderer.srcObject = stream;
    notifyListeners();
  }

  void _signal(_GroupPeer peer, Map<String, dynamic> signal) =>
      _send('group_call_signal', {
        ..._lease,
        'to': peer.member.user,
        'toSession': peer.member.sessionId,
        'signal': signal,
      });
  void _sendDescription(_GroupPeer peer, RTCSessionDescription description) {
    _signal(peer, {'kind': description.type, 'sdp': description.sdp});
    peer.localSet = true;
    for (final candidate in peer.localIce) {
      _signal(peer, {'kind': 'ice', 'candidate': candidate});
    }
    peer.localIce.clear();
  }

  Future<void> _addIce(_GroupPeer peer, Map<String, dynamic> c) async {
    try {
      await peer.connection.addCandidate(
        RTCIceCandidate(
          c['candidate']?.toString(),
          c['sdpMid']?.toString(),
          c['sdpMLineIndex'] as int?,
        ),
      );
    } catch (_) {
      debugPrint('Group call ICE candidate was not applied');
    }
  }

  Future<void> leave({String? message, bool endForAll = false}) {
    if (_leaving != null) return _leaving!;
    final future = _leave(message, endForAll: endForAll);
    _leaving = future;
    return future.whenComplete(() => _leaving = null);
  }

  Future<void> _leave(String? message, {bool endForAll = false}) async {
    final old = current;
    ++_epoch;
    _clearReconnectIntent();
    if (old != null) {
      _dismissed.add(old.id);
      if (_dismissed.length > 100) _dismissed.remove(_dismissed.first);
    }
    if (sessionId != null && old != null) {
      _send('group_call_leave', {..._lease, 'endForAll': endForAll});
    }
    _clearPendingJoin();
    _waitTimer?.cancel();
    _heartbeat?.cancel();
    _clockTimer?.cancel();
    _stopSpeakingMonitor();
    _controlsTimer?.cancel();
    _clock.stop();
    phase = GroupCallPhase.leaving;
    notifyListeners();
    final peers = _peers.values.toList();
    _peers.clear();
    _peerReconnectAttempts.clear();
    _pendingSignals.clear();
    final stream = _stream;
    _stream = null;
    try {
      await IncomingCallAlertService.instance.stop().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}
    for (final peer in peers) {
      await _releasePeer(peer).timeout(const Duration(seconds: 3));
    }
    for (final renderer in remoteVideos.values) {
      try {
        renderer.srcObject = null;
        await renderer.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    remoteVideos.clear();
    if (stream != null) {
      try {
        await _releaseStream(stream).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    if (_renderLocalVideo && localVideo != null) {
      try {
        localVideo!.srcObject = null;
        await localVideo!.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
      localVideo = null;
    }
    if (stream != null && Platform.isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice().timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
    }
    sessionId = null;
    current = null;
    groupId = null;
    _requestId = null;
    _transitioningViewerToStage = false;
    _transitionGroupId = null;
    _expectedLeftSessions.clear();
    featuredUser = null;
    layout = GroupCallLayout.stage;
    phase = GroupCallPhase.idle;
    notifyListeners();
    if (message != null) _notifyError(message);
  }

  Future<void> _releasePeer(_GroupPeer peer) async {
    peer.timeout?.cancel();
    final renderer = remoteVideos.remove(peer.member.user);
    if (renderer != null) {
      try {
        renderer.srcObject = null;
        await renderer.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    try {
      await peer.connection.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await peer.connection.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    try {
      await stream.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
