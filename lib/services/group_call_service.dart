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

enum GroupCallPhase { idle, invited, joining, active, leaving }

class _GroupPeer {
  _GroupPeer(this.member, this.connection);
  final GroupCallMember member;
  final RTCPeerConnection connection;
  final List<Map<String, dynamic>> localIce = [], remoteIce = [];
  bool localSet = false, remoteSet = false;
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
      _media = (() => navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
          'frameRate': {'ideal': 20, 'max': 24},
        },
      })),
      _connection = (() => createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
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
       _media = media,
       _connection = connection;

  static final instance = GroupCallService._();
  final void Function(String, Map<String, dynamic>) _send;
  final String Function() _user;
  final bool Function() _authenticated, _privateBusy, _foreground;
  final Future<MediaStream> Function() _media;
  final Future<RTCPeerConnection> Function() _connection;
  final Map<String, GroupCallState> rooms = {};
  final Map<String, _GroupPeer> _peers = {};
  final Map<String, RTCVideoRenderer> remoteVideos = {};
  final Set<String> _dismissed = {};
  Future<void> _events = Future.value();
  Future<void>? _leaving;
  MediaStream? _stream;
  Timer? _waitTimer, _heartbeat, _clockTimer;
  final Stopwatch _clock = Stopwatch();
  int _epoch = 0;
  bool _initialized = false, _speakerChanging = false;
  String? _requestId;
  String? sessionId;
  String? groupId;
  GroupCallState? current;
  String groupName = 'Групповой звонок';
  GroupCallPhase phase = GroupCallPhase.idle;
  bool supported = false, microphoneEnabled = true, speakerphoneEnabled = false;
  bool videoEnabled = true;
  String? notice;
  int noticeSerial = 0;
  bool get hasCall => phase != GroupCallPhase.idle;
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
    if (_authenticated()) _send('group_call_sync', {});
  }

  void requestState(String id) {
    if (_authenticated()) _send('group_call_get', {'groupId': id});
  }

  void _notifyError(String message) {
    notice = message;
    noticeSerial++;
    notifyListeners();
  }

  Future<void> begin(String id, String name, {String? existingCallId, bool withVideo = true}) async {
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
    if (_privateBusy() || (hasCall && phase != GroupCallPhase.invited)) {
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
    speakerphoneEnabled = false;
    _clock.reset();
    notifyListeners();
    try {
      await IncomingCallAlertService.instance.stop();
      if (epoch != _epoch) return;
      if (Platform.isAndroid)
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      if (epoch != _epoch) return;
      final stream = await _media();
      if (!withVideo) {
        for (final track in stream.getVideoTracks()) {
          track.enabled = false;
          await track.stop();
        }
      }
      if (epoch != _epoch) {
        await _releaseStream(stream);
        return;
      }
      _stream = stream;
      if (canSwitchSpeaker) await Helper.setSpeakerphoneOn(false);
      if (epoch != _epoch) return;
      _send(existingCallId == null ? 'group_call_start' : 'group_call_join', {
        'groupId': id,
        'callId': existingCallId,
        'requestId': _requestId,
      });
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
          message:
              'Не удалось включить микрофон. Проверьте разрешение приложения.',
        );
    }
  }

  Future<void> accept({bool withVideo = true}) async {
    final room = current;
    if (phase == GroupCallPhase.invited && room != null) {
      await begin(room.groupId, room.name, existingCallId: room.id, withVideo: withVideo);
    }
  }

  Map<String, dynamic> get _lease => {
    'groupId': groupId,
    'callId': current?.id,
    'sessionId': sessionId,
  };

  void toggleMicrophone() {
    if (_stream == null || phase != GroupCallPhase.active) return;
    microphoneEnabled = !microphoneEnabled;
    for (final track in _stream!.getAudioTracks()) {
      track.enabled = microphoneEnabled;
    }
    _send('group_call_mute', {..._lease, 'muted': !microphoneEnabled});
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    if (!canSwitchSpeaker || _speakerChanging) return;
    final epoch = _epoch;
    _speakerChanging = true;
    try {
      await Helper.setSpeakerphoneOn(!speakerphoneEnabled);
      if (epoch == _epoch) {
        speakerphoneEnabled = !speakerphoneEnabled;
        notifyListeners();
      }
    } catch (_) {
      if (epoch == _epoch) _notifyError('Не удалось переключить динамик');
    } finally {
      _speakerChanging = false;
    }
  }

  void _onMessage(Map<String, dynamic> packet) {
    unawaited(handlePacket(packet));
  }

  @visibleForTesting
  Future<void> handlePacket(Map<String, dynamic> packet) {
    _events = _events.then((_) => _handle(packet)).catchError((Object _) {
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
      _send('group_call_sync', {});
      return;
    }
    if (type == 'disconnected') {
      supported = false;
      rooms.clear();
      if (hasCall)
        await leave(message: 'Соединение прервано. Войдите в звонок повторно.');
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
      notifyListeners();
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
    if (type == 'group_call_joined') {
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
      final epoch = _epoch;
      _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
        if (epoch == _epoch) _send('group_call_heartbeat', _lease);
      });
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (epoch == _epoch) notifyListeners();
      });
      await _applyState(room);
      notifyListeners();
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
      if (peer == null ||
          data['fromSession'] != peer.member.sessionId ||
          data['signal'] is! Map)
        return;
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
      } else if (signal['kind'] == 'offer' || signal['kind'] == 'answer') {
        final offer = signal['kind'] == 'offer';
        if (peer.remoteSet ||
            offer ==
                GroupCallState.makesOffer(sessionId!, peer.member.sessionId))
          return;
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
    }
  }

  Future<void> _applyState(GroupCallState room) async {
    final epoch = _epoch;
    if (room.member(user)?.sessionId != sessionId) {
      await leave(message: 'Вы больше не участвуете в звонке');
      return;
    }
    current = room;
    rooms[room.groupId] = room;
    for (final peer in _peers.values.toList()) {
      if (room.member(peer.member.user)?.sessionId != peer.member.sessionId) {
        _peers.remove(peer.member.user);
        await _releasePeer(peer);
      }
    }
    for (final member in room.members) {
      if (epoch != _epoch || _stream == null) return;
      if (member.user == user || _peers.containsKey(member.user)) continue;
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
      pc.onTrack = (event) {
        if (!valid()) return;
        if (event.track.kind == 'audio') event.track.enabled = true;
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          unawaited(_attachRemoteVideo(peer.member.user, event.streams.first));
        }
      };
      pc.onConnectionState = (state) {
        if (!valid()) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          peer.timeout?.cancel();
          peer.status = 'В сети';
          _clock.start();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          peer.status = 'Связь прервалась';
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          peer.status = 'Нет связи — войдите снова';
        }
        notifyListeners();
      };
      peer.timeout = Timer(const Duration(seconds: 35), () {
        if (valid() && peer.status != 'В сети') {
          peer.status = 'Нет связи — войдите снова';
          notifyListeners();
        }
      });
      for (final track in _stream!.getTracks()) {
        if (!valid()) return;
        await pc.addTrack(track, _stream!);
      }
      if (valid() && GroupCallState.makesOffer(sessionId!, member.sessionId)) {
        final offer = await pc.createOffer();
        if (!valid()) return;
        await pc.setLocalDescription(offer);
        if (valid()) _sendDescription(peer, offer);
      }
    }
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

  Future<void> leave({String? message}) {
    if (_leaving != null) return _leaving!;
    final future = _leave(message);
    _leaving = future;
    return future.whenComplete(() => _leaving = null);
  }

  Future<void> _leave(String? message) async {
    final old = current;
    ++_epoch;
    if (old != null) {
      _dismissed.add(old.id);
      if (_dismissed.length > 100) _dismissed.remove(_dismissed.first);
    }
    if (sessionId != null && old != null) _send('group_call_leave', _lease);
    _waitTimer?.cancel();
    _heartbeat?.cancel();
    _clockTimer?.cancel();
    _clock.stop();
    phase = GroupCallPhase.leaving;
    notifyListeners();
    final peers = _peers.values.toList();
    _peers.clear();
    final stream = _stream;
    _stream = null;
    await IncomingCallAlertService.instance.stop();
    for (final peer in peers) {
      await _releasePeer(peer);
    }
    for (final renderer in remoteVideos.values) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
    remoteVideos.clear();
    if (stream != null) await _releaseStream(stream);
    if (stream != null && Platform.isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
    sessionId = null;
    current = null;
    groupId = null;
    _requestId = null;
    phase = GroupCallPhase.idle;
    notifyListeners();
    if (message != null) _notifyError(message);
  }

  Future<void> _releasePeer(_GroupPeer peer) async {
    peer.timeout?.cancel();
    try {
      await peer.connection.close();
    } catch (_) {}
    try {
      await peer.connection.dispose();
    } catch (_) {}
  }

  Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {}
    }
    try {
      await stream.dispose();
    } catch (_) {}
  }
}
