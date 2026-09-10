import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'socket_service.dart';
import 'incoming_call_alert_service.dart';
import 'app_visibility.dart';
import 'call_clock.dart';
import 'storage_service.dart';
import 'system_call_service.dart';
import 'notification_service.dart';
import 'call_result.dart';

enum CallPhase { idle, incoming, outgoing, connecting, active, ended }

class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _fallbackRemoteStream;
  Map<String, dynamic>? _pendingOffer;
  final List<Map<String, dynamic>> _pendingCandidates = [];
  final List<Map<String, dynamic>> _localCandidates = [];
  Future<void>? _rendererInitialization;
  Timer? _timeout;
  Timer? _disconnectTimeout;
  Timer? _clockTick;
  final CallClock clock = CallClock();
  Uint8List? avatarBytes;
  Map<String, dynamic>? _incomingData;
  final Set<String> _dismissedCalls = {};
  bool _initialized = false;
  bool _remoteDescriptionSet = false;
  bool _localDescriptionSent = false;
  bool _answerApplying = false;
  bool _cleaning = false;
  CallPhase phase = CallPhase.idle;
  String? callId;
  String? peerUser;
  bool isVideo = false;
  bool isIncoming = false;
  bool microphoneEnabled = true;
  bool cameraEnabled = true;
  bool speakerphoneEnabled = false;
  bool _speakerChanging = false;
  bool _mediaReady = false;
  bool _accepted = false;
  CallResult? lastFinishedCall;
  CallOutcome? outcome;
  bool get canSwitchSpeaker =>
      (Platform.isAndroid || Platform.isIOS) && _mediaReady;
  String statusText = '';
  bool get hasCall => phase != CallPhase.idle;
  bool get shouldShowCallScreen => hasCall && phase != CallPhase.ended;
  bool Function() externalCallBusy = () => false;
  bool get canSwitchCamera => Platform.isAndroid || Platform.isIOS;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    SocketService.instance.addMessageHandler(_handleSocketMessage);
    SystemCallService.instance.onAccept = (id) {
      if (callId == id &&
          phase == CallPhase.incoming &&
          AppVisibility.instance.foreground) {
        unawaited(acceptIncoming());
      } else if (!hasCall) {
        SocketService.instance.requestPendingCall(id);
      }
    };
    SystemCallService.instance.onEnd = (id) {
      if (callId == id) {
        unawaited(phase == CallPhase.incoming ? declineIncoming() : hangUp());
      }
    };
    SystemCallService.instance.onTimeout = (id) {
      if (callId == id && phase == CallPhase.incoming) {
        _sendEnd(id);
        unawaited(
          _finishWithMessage('Пропущенный звонок', result: CallOutcome.missed),
        );
      }
    };
    SystemCallService.instance.onRemoteCancel = (id) {
      if (callId == id)
        _handleRemoteEnd({'callId': id, 'from': peerUser}, 'Звонок завершён');
    };
    AppVisibility.instance.changes.addListener(() {
      if (phase != CallPhase.incoming) return;
      if (AppVisibility.instance.foreground) {
        if (SystemCallService.instance.acceptedId == callId)
          unawaited(acceptIncoming());
      } else if (_incomingData != null && Platform.isAndroid) {
        unawaited(_alertIncoming(callId!));
      }
    });
  }

  bool _isCurrent(String id) =>
      callId == id &&
      !_cleaning &&
      phase != CallPhase.idle &&
      phase != CallPhase.ended;

  Future<void> startCall({required String peer, required bool video}) async {
    final target = peer.trim();
    if (target.isEmpty ||
        hasCall ||
        externalCallBusy() ||
        !SocketService.instance.isAuthenticated)
      return;
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    callId = id;
    peerUser = target;
    _loadAvatar(target);
    SocketService.instance.requestAvatar(target);
    isVideo = video;
    isIncoming = false;
    _accepted = false;
    outcome = null;
    speakerphoneEnabled = video;
    microphoneEnabled = true;
    cameraEnabled = video;
    phase = CallPhase.outgoing;
    statusText = video ? 'Видеозвонок…' : 'Аудиозвонок…';
    _armTimeout(id, const Duration(seconds: 75), 'Нет ответа');
    notifyListeners();
    try {
      final connection = await _prepareConnection(id, video: video);
      if (connection == null || !_isCurrent(id)) return;
      final description = await connection.createOffer();
      if (!_isCurrent(id)) return;
      await connection.setLocalDescription(description);
      if (!_isCurrent(id)) return;
      SocketService.instance.sendCallOffer(
        to: target,
        callId: id,
        video: video,
        sdp: {'type': description.type, 'sdp': description.sdp},
      );
      // ICE may be emitted during setLocalDescription: always send SDP first.
      _flushLocalCandidates(id);
      statusText = 'Ожидание ответа…';
      notifyListeners();
    } catch (error) {
      if (_isCurrent(id)) {
        _sendEnd(id);
        await _finishWithMessage(_readableError(error));
      }
    }
  }

  Future<void> acceptIncoming() async {
    if (phase != CallPhase.incoming ||
        _pendingOffer == null ||
        peerUser == null ||
        callId == null)
      return;
    final offer = _pendingOffer!;
    final target = peerUser!;
    final id = callId!;
    if (!SocketService.instance.isAuthenticated) {
      SystemCallService.instance.acceptedId = id;
      statusText = 'Восстановление связи с сервером…';
      await IncomingCallAlertService.instance.stop();
      notifyListeners();
      return;
    }
    phase = CallPhase.connecting;
    _accepted = true;
    statusText = 'Подключение…';
    _armTimeout(
      id,
      const Duration(seconds: 45),
      'Не удалось установить соединение',
    );
    notifyListeners();
    try {
      await IncomingCallAlertService.instance.stop();
      await SystemCallService.instance.silence(id);
      if (!_isCurrent(id)) return;
      final connection = await _prepareConnection(id, video: isVideo);
      if (connection == null || !_isCurrent(id)) return;
      await connection.setRemoteDescription(
        RTCSessionDescription(offer['sdp']?.toString(), 'offer'),
      );
      if (!_isCurrent(id)) return;
      _remoteDescriptionSet = true;
      await _flushPendingCandidates(id, connection);
      if (!_isCurrent(id)) return;
      final answer = await connection.createAnswer();
      if (!_isCurrent(id)) return;
      await connection.setLocalDescription(answer);
      if (!_isCurrent(id)) return;
      SocketService.instance.sendCallAnswer(
        to: target,
        callId: id,
        sdp: {'type': answer.type, 'sdp': answer.sdp},
      );
      _flushLocalCandidates(id);
      _pendingOffer = null;
      if (phase != CallPhase.active) statusText = 'Соединение…';
      notifyListeners();
    } catch (error) {
      if (_isCurrent(id)) {
        SocketService.instance.sendCallReject(
          to: target,
          callId: id,
          reason: 'media_error',
        );
        await _finishWithMessage(_readableError(error));
      }
    }
  }

  Future<void> declineIncoming() async {
    if (peerUser != null && callId != null) {
      SocketService.instance.sendCallReject(to: peerUser!, callId: callId!);
    }
    _recordFinished(CallOutcome.declined, 'Вызов отклонён');
    await _cleanup();
  }

  Future<void> hangUp() async {
    if (callId != null) _sendEnd(callId!);
    _recordFinished(
      clock.connected
          ? CallOutcome.completed
          : isIncoming
          ? CallOutcome.declined
          : CallOutcome.cancelled,
      'Звонок завершён',
    );
    await _cleanup();
  }

  Future<void> toggleSpeakerphone() async {
    final id = callId;
    if (id == null || !_isCurrent(id) || !canSwitchSpeaker || _speakerChanging)
      return;
    _speakerChanging = true;
    final next = !speakerphoneEnabled;
    try {
      await Helper.setSpeakerphoneOn(next);
      if (_isCurrent(id)) speakerphoneEnabled = next;
    } catch (_) {
      if (_isCurrent(id)) statusText = 'Не удалось переключить динамик';
    } finally {
      _speakerChanging = false;
      notifyListeners();
    }
  }

  void _sendEnd(String id) {
    if (id == callId && peerUser != null) {
      SocketService.instance.sendCallEnd(to: peerUser!, callId: id);
    }
  }

  void toggleMicrophone() {
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    microphoneEnabled = !microphoneEnabled;
    for (final track in tracks) {
      track.enabled = microphoneEnabled;
    }
    notifyListeners();
  }

  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    cameraEnabled = !cameraEnabled;
    for (final track in tracks) {
      track.enabled = cameraEnabled;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty || !canSwitchCamera) return;
    final id = callId;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {
      if (id != null && _isCurrent(id)) {
        statusText = 'Не удалось переключить камеру';
        notifyListeners();
      }
    }
  }

  Future<RTCPeerConnection?> _prepareConnection(
    String id, {
    required bool video,
  }) async {
    if (Platform.isAndroid) {
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );
      if (!_isCurrent(id)) return null;
    }
    _rendererInitialization ??= _initializeRenderers();
    await _rendererInitialization;
    if (!_isCurrent(id)) return null;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            }
          : false,
    });
    // A permission dialog can outlive the call. Never retain its camera/mic.
    if (!_isCurrent(id)) {
      await _disposeStream(stream);
      return null;
    }
    _localStream = stream;
    localRenderer.srcObject = stream;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await Helper.setSpeakerphoneOn(speakerphoneEnabled);
      } catch (_) {
        debugPrint('Call audio route selection unavailable');
      }
      if (!_isCurrent(id)) return null;
    }
    _mediaReady = true;
    final connection = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
    });
    if (!_isCurrent(id)) {
      await connection.close();
      await connection.dispose();
      return null;
    }
    _peerConnection = connection;
    connection.onIceCandidate = (candidate) {
      if (!_isCurrent(id) || candidate.candidate?.isNotEmpty != true) return;
      final data = <String, dynamic>{
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      if (!_localDescriptionSent) {
        if (_localCandidates.length < 256) _localCandidates.add(data);
      } else {
        SocketService.instance.sendCallIceCandidate(
          to: peerUser!,
          callId: id,
          candidate: data,
        );
      }
    };
    connection.onAddStream = (stream) {
      if (!_isCurrent(id)) return;
      remoteRenderer.srcObject = stream;
      notifyListeners();
    };
    connection.onTrack = (event) {
      unawaited(_attachRemoteTrack(id, event));
    };
    connection.onConnectionState = (state) {
      if (!_isCurrent(id)) return;
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _timeout?.cancel();
          _disconnectTimeout?.cancel();
          phase = CallPhase.active;
          statusText = 'Соединено';
          if (!clock.connected) {
            clock.connect();
            _clockTick = Timer.periodic(const Duration(seconds: 1), (_) {
              if (_isCurrent(id)) notifyListeners();
            });
            SocketService.instance.sendCallConnected(to: peerUser!, callId: id);
            unawaited(SystemCallService.instance.connected(id));
          }
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          phase = CallPhase.connecting;
          statusText = 'Восстановление соединения…';
          _disconnectTimeout?.cancel();
          _disconnectTimeout = Timer(const Duration(seconds: 15), () {
            if (_isCurrent(id)) {
              _sendEnd(id);
              unawaited(_finishWithMessage('Соединение потеряно'));
            }
          });
          notifyListeners();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _sendEnd(id);
          unawaited(_finishWithMessage('Соединение завершено'));
          break;
        default:
          break;
      }
    };
    for (final track in stream.getTracks()) {
      if (!_isCurrent(id)) return null;
      await connection.addTrack(track, stream);
    }
    if (!_isCurrent(id)) return null;
    notifyListeners();
    return connection;
  }

  Future<void> _initializeRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> _attachRemoteTrack(String id, RTCTrackEvent event) async {
    if (!_isCurrent(id)) return;
    MediaStream? stream = event.streams.isNotEmpty
        ? event.streams.first
        : _fallbackRemoteStream;
    if (stream == null) {
      try {
        stream = await createLocalMediaStream('spartan_remote_$id');
      } catch (error) {
        debugPrint('Remote media stream could not be created: $error');
        return;
      }
      if (!_isCurrent(id)) {
        await _cleanupStep(stream.dispose());
        return;
      }
      _fallbackRemoteStream = stream;
    }
    if (event.streams.isEmpty &&
        !stream.getTracks().any((track) => track.id == event.track.id)) {
      try {
        await stream.addTrack(event.track);
      } catch (error) {
        debugPrint('Remote media track could not be attached: $error');
        return;
      }
    }
    if (!_isCurrent(id)) return;
    event.track.enabled = true;
    remoteRenderer.srcObject = stream;
    // onTrack may fire before ICE connects; it does not mean connected.
    notifyListeners();
  }

  void _flushLocalCandidates(String id) {
    if (!_isCurrent(id)) return;
    _localDescriptionSent = true;
    for (final candidate in _localCandidates) {
      SocketService.instance.sendCallIceCandidate(
        to: peerUser!,
        callId: id,
        candidate: candidate,
      );
    }
    _localCandidates.clear();
  }

  void _handleSocketMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    final rawData = message['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
    switch (type) {
      case 'call_offer':
        _handleIncomingOffer(data);
        break;
      case 'login_success':
        unawaited(SystemCallService.instance.restorePending());
        SocketService.instance.requestPendingCall();
        break;
      case 'pending_call_empty':
        if (!hasCall)
          unawaited(
            SystemCallService.instance.end(SystemCallService.instance.nativeId),
          );
        break;
      case 'avatar_data':
      case 'avatar_updated':
        if (peerUser != null) {
          _loadAvatar(peerUser!);
          notifyListeners();
        }
        break;
      case 'call_answer':
        unawaited(_handleAnswer(data));
        break;
      case 'call_ice_candidate':
        unawaited(_handleIceCandidate(data));
        break;
      case 'call_reject':
        _handleRemoteEnd(
          data,
          data['reason'] == 'busy' ? 'Пользователь занят' : 'Вызов отклонён',
        );
        break;
      case 'call_unavailable':
        _handleRemoteEnd(data, 'Пользователь не в сети');
        break;
      case 'call_end':
        _handleRemoteEnd(data, 'Звонок завершён');
        break;
      case 'call_error':
        if (_matchesCurrentCall(data, requirePeer: false)) {
          unawaited(
            _finishWithMessage(data['reason']?.toString() ?? 'Ошибка звонка'),
          );
        }
        break;
      case 'disconnected':
        if (Platform.isAndroid &&
            phase == CallPhase.incoming &&
            _incomingData != null) {
          break;
        }
        if (hasCall) unawaited(_finishWithMessage('Потеряна связь с сервером'));
        break;
    }
  }

  void _handleIncomingOffer(Map<String, dynamic> data) {
    final id = data['callId']?.toString().trim() ?? '';
    final from = data['from']?.toString().trim() ?? '';
    if (_dismissedCalls.contains(id)) {
      SocketService.instance.sendCallReject(to: from, callId: id);
      return;
    }
    final rawSdp = data['sdp'];
    final sdp = rawSdp is Map
        ? Map<String, dynamic>.from(rawSdp)
        : <String, dynamic>{};
    if (id.isEmpty ||
        from.isEmpty ||
        sdp['type'] != 'offer' ||
        sdp['sdp']?.toString().isNotEmpty != true)
      return;
    if (externalCallBusy()) {
      SocketService.instance.sendCallReject(
        to: from,
        callId: id,
        reason: 'busy',
      );
      return;
    }
    if (hasCall) {
      if (id == callId &&
          from == peerUser &&
          phase == CallPhase.incoming &&
          SystemCallService.instance.acceptedId == id &&
          AppVisibility.instance.foreground) {
        unawaited(acceptIncoming());
      }
      if (id != callId || from != peerUser) {
        SocketService.instance.sendCallReject(
          to: from,
          callId: id,
          reason: 'busy',
        );
      }
      return;
    }
    callId = id;
    peerUser = from;
    _loadAvatar(from);
    SocketService.instance.requestAvatar(from);
    _incomingData = data;
    isVideo = data['video'] == true;
    isIncoming = true;
    _accepted = false;
    outcome = null;
    speakerphoneEnabled = isVideo;
    microphoneEnabled = true;
    cameraEnabled = isVideo;
    _pendingOffer = sdp;
    phase = CallPhase.incoming;
    statusText = isVideo ? 'Входящий видеозвонок' : 'Входящий аудиозвонок';
    final expires = int.tryParse('${data['expiresAt']}');
    final remaining = expires == null
        ? 75000
        : expires - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      unawaited(_cleanup());
      return;
    }
    _armTimeout(
      id,
      Duration(milliseconds: remaining.clamp(1, 75000)),
      'Пропущенный звонок',
    );
    if (SystemCallService.instance.acceptedId == id &&
        AppVisibility.instance.foreground) {
      unawaited(acceptIncoming());
    } else {
      unawaited(_alertIncoming(id));
    }
    notifyListeners();
  }

  void _loadAvatar(String user) {
    try {
      final raw = StorageService.getAvatar(user);
      avatarBytes = raw == null
          ? null
          : base64Decode(raw.contains(',') ? raw.split(',').last : raw);
    } catch (_) {
      avatarBytes = null;
    }
  }

  Future<void> _alertIncoming(String id) async {
    if (Platform.isAndroid) {
      if (await SystemCallService.instance.isNative(id)) return;
      if (!_isCurrent(id) || phase != CallPhase.incoming) return;
      if (!AppVisibility.instance.foreground && _incomingData != null) {
        await IncomingCallAlertService.instance.stop();
        final data = {
          ..._incomingData!,
          'sender': peerUser,
          'type': 'call_invite',
        };
        await SystemCallService.showIncoming(data);
        if (!_isCurrent(id) || phase != CallPhase.incoming)
          await SystemCallService.instance.end(id);
        return;
      }
    }
    if (!_isCurrent(id) || phase != CallPhase.incoming) return;
    await IncomingCallAlertService.instance.start(id);
    if (Platform.isWindows && _isCurrent(id) && phase == CallPhase.incoming) {
      await AppVisibility.flashWindow();
      await NotificationService.instance.showIncomingCall(
        id: id,
        from: peerUser!,
        video: isVideo,
      );
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    if (!_matchesCurrentCall(data) ||
        isIncoming ||
        _answerApplying ||
        _remoteDescriptionSet)
      return;
    final rawSdp = data['sdp'];
    final sdp = rawSdp is Map
        ? Map<String, dynamic>.from(rawSdp)
        : <String, dynamic>{};
    final connection = _peerConnection;
    if (connection == null ||
        sdp['type'] != 'answer' ||
        sdp['sdp']?.toString().isNotEmpty != true)
      return;
    final id = callId!;
    _answerApplying = true;
    phase = CallPhase.connecting;
    statusText = 'Соединение…';
    _armTimeout(
      id,
      const Duration(seconds: 45),
      'Не удалось установить соединение',
    );
    notifyListeners();
    try {
      await connection.setRemoteDescription(
        RTCSessionDescription(sdp['sdp']?.toString(), 'answer'),
      );
      if (!_isCurrent(id)) return;
      _remoteDescriptionSet = true;
      await _flushPendingCandidates(id, connection);
    } catch (error) {
      if (_isCurrent(id)) {
        _sendEnd(id);
        await _finishWithMessage(_readableError(error));
      }
    } finally {
      if (id == callId) _answerApplying = false;
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    if (!_matchesCurrentCall(data)) return;
    final rawCandidate = data['candidate'];
    final candidate = rawCandidate is Map
        ? Map<String, dynamic>.from(rawCandidate)
        : <String, dynamic>{};
    if (candidate['candidate']?.toString().isNotEmpty != true) return;
    final connection = _peerConnection;
    if (connection == null || !_remoteDescriptionSet) {
      if (_pendingCandidates.length < 256) _pendingCandidates.add(candidate);
      return;
    }
    await _addCandidate(connection, candidate);
  }

  Future<void> _flushPendingCandidates(
    String id,
    RTCPeerConnection connection,
  ) async {
    final queued = List<Map<String, dynamic>>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in queued) {
      if (!_isCurrent(id)) return;
      await _addCandidate(connection, candidate);
    }
  }

  Future<void> _addCandidate(
    RTCPeerConnection connection,
    Map<String, dynamic> data,
  ) async {
    try {
      await connection.addCandidate(
        RTCIceCandidate(
          data['candidate']?.toString(),
          data['sdpMid']?.toString(),
          int.tryParse(data['sdpMLineIndex']?.toString() ?? ''),
        ),
      );
    } catch (_) {
      // Late ICE after native teardown is harmless; timeout handles failure.
      debugPrint('Call ICE candidate could not be applied');
    }
  }

  bool _matchesCurrentCall(
    Map<String, dynamic> data, {
    bool requirePeer = true,
  }) {
    final id = data['callId']?.toString().trim() ?? '';
    return _isCurrent(id) && (!requirePeer || data['from'] == peerUser);
  }

  void _handleRemoteEnd(Map<String, dynamic> data, String message) {
    if (!_matchesCurrentCall(data)) return;
    final result = CallResult.remoteEnd(
      incoming: isIncoming,
      connected: clock.connected,
      accepted: _accepted,
    );
    unawaited(
      _finishWithMessage(
        result == CallOutcome.missed ? 'Пропущенный звонок' : message,
        result: result,
      ),
    );
  }

  void _armTimeout(String id, Duration duration, String message) {
    _timeout?.cancel();
    _timeout = Timer(duration, () {
      if (_isCurrent(id)) {
        _sendEnd(id);
        unawaited(
          _finishWithMessage(
            message,
            result: isIncoming && !_accepted
                ? CallOutcome.missed
                : CallOutcome.failed,
          ),
        );
      }
    });
  }

  void _recordFinished(CallOutcome result, String message) {
    if (callId == null || peerUser == null || outcome != null) return;
    outcome = result;
    clock.stop();
    lastFinishedCall = CallResult(
      id: callId!,
      peer: peerUser!,
      video: isVideo,
      incoming: isIncoming,
      outcome: result,
      duration: clock.elapsed,
      message: message,
    );
    phase = CallPhase.ended;
    statusText = message;
    notifyListeners();
    if (result == CallOutcome.missed) {
      unawaited(
        SystemCallService.showMissedCall(
          id: callId!,
          from: peerUser!,
          video: isVideo,
        ),
      );
    }
  }

  Future<void> _finishWithMessage(
    String message, {
    CallOutcome result = CallOutcome.failed,
  }) async {
    final id = callId;
    if (id == null || !_isCurrent(id)) return;
    _recordFinished(clock.connected ? CallOutcome.completed : result, message);
    if (callId == id) await _cleanup();
  }

  Future<void> _cleanupStep(
    Future<void> operation, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      await operation.timeout(timeout);
    } catch (error) {
      debugPrint('Call cleanup step skipped: $error');
    }
  }

  Future<void> _disposeStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {
        /* Already stopped. */
      }
    }
    try {
      await stream.dispose();
    } catch (_) {
      /* Already disposed. */
    }
  }

  Future<void> _releaseMedia() async {
    final connection = _peerConnection;
    final stream = _localStream;
    final fallbackRemoteStream = _fallbackRemoteStream;
    _peerConnection = null;
    _localStream = null;
    _fallbackRemoteStream = null;
    _mediaReady = false;
    if (connection != null) {
      connection.onIceCandidate = null;
      connection.onAddStream = null;
      connection.onTrack = null;
      connection.onConnectionState = null;
    }
    if (localRenderer.textureId != null) localRenderer.srcObject = null;
    if (remoteRenderer.textureId != null) remoteRenderer.srcObject = null;
    if (stream != null) await _disposeStream(stream);
    try {
      await connection?.close();
    } catch (_) {
      /* Best effort. */
    }
    try {
      await connection?.dispose();
    } catch (_) {
      /* Best effort. */
    }
    if (fallbackRemoteStream != null) {
      await _cleanupStep(fallbackRemoteStream.dispose());
    }
    if (Platform.isAndroid && stream != null) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
  }

  Future<void> _cleanup() async {
    if (_cleaning) return;
    _cleaning = true;
    final endingCallId = callId;
    try {
      if (endingCallId != null) {
        _dismissedCalls.add(endingCallId);
        if (_dismissedCalls.length > 32) {
          _dismissedCalls.remove(_dismissedCalls.first);
        }
      }
      phase = CallPhase.ended;
      _clockTick?.cancel();
      _timeout?.cancel();
      _disconnectTimeout?.cancel();
      notifyListeners();
      if (Platform.isAndroid && endingCallId != null) {
        await _cleanupStep(
          const MethodChannel('spartan_chat/call_window')
              .invokeMethod<void>('hide', {'callId': endingCallId}),
        );
      }
      await _cleanupStep(IncomingCallAlertService.instance.stop());
      await _cleanupStep(SystemCallService.instance.end(endingCallId));
      await _cleanupStep(_releaseMedia(), timeout: const Duration(seconds: 4));
    } finally {
      clock.reset();
      _pendingOffer = null;
      _incomingData = null;
      avatarBytes = null;
      _pendingCandidates.clear();
      _localCandidates.clear();
      _remoteDescriptionSet = false;
      _localDescriptionSent = false;
      _answerApplying = false;
      callId = null;
      peerUser = null;
      isVideo = false;
      isIncoming = false;
      _accepted = false;
      speakerphoneEnabled = false;
      _speakerChanging = false;
      microphoneEnabled = true;
      cameraEnabled = true;
      statusText = '';
      phase = CallPhase.idle;
      _cleaning = false;
      notifyListeners();
    }
  }

  String _readableError(Object error) {
    final text = error.toString().replaceFirst('Bad state: ', '').trim();
    if (text.toLowerCase().contains('permission') ||
        text.toLowerCase().contains('denied')) {
      return isVideo
          ? 'Разрешите доступ к камере и микрофону'
          : 'Разрешите доступ к микрофону';
    }
    return text.isEmpty ? 'Не удалось начать звонок' : text;
  }
}
