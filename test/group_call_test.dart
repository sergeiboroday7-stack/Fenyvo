import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:spartan_chat_final/services/group_call_service.dart';
import 'package:spartan_chat_final/services/group_call_state.dart';
import 'package:spartan_chat_final/screens/group_call_screen.dart';
import 'package:spartan_chat_final/theme/spartan_theme.dart';

class Track extends Fake implements MediaStreamTrack {
  @override
  bool enabled = true;
  bool stopped = false;
  @override
  Future<void> stop() async {
    stopped = true;
  }
}

class Stream extends Fake implements MediaStream {
  final track = Track();
  bool released = false;
  @override
  List<MediaStreamTrack> getTracks() => [track];
  @override
  List<MediaStreamTrack> getAudioTracks() => [track];
  @override
  Future<void> dispose() async {
    released = true;
  }
}

class Sender extends Fake implements RTCRtpSender {}

class Peer extends Fake implements RTCPeerConnection {
  @override
  Function(RTCIceCandidate)? onIceCandidate;
  @override
  Function(RTCTrackEvent)? onTrack;
  @override
  Function(RTCPeerConnectionState)? onConnectionState;
  final events = <String>[];
  bool closed = false;
  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async => Sender();
  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('offer-sdp', 'offer');
  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('answer-sdp', 'answer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    events.add('local-${description.type}');
    onIceCandidate?.call(RTCIceCandidate('local-ice', '0', 0));
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    events.add('remote-${description.type}');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate c) async {
    events.add('ice');
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {}
}

Map<String, dynamic> room({
  String local = 'a',
  String remote = 'b',
  bool includeRemote = true,
}) => {
  'id': 'call',
  'groupId': 'g',
  'name': 'Spartan 1',
  'startedBy': 'A',
  'participants': [
    {'user': 'A', 'sessionId': local, 'muted': false},
    if (includeRemote) {'user': 'B', 'sessionId': remote, 'muted': false},
  ],
};

class Fixture {
  final stream = Stream();
  final peers = <Peer>[];
  final sent = <Map<String, dynamic>>[];
  late final service = GroupCallService.forTesting(
    send: (type, data) => sent.add({'type': type, 'data': data}),
    user: 'A',
    media: () async => stream,
    connection: () async {
      final pc = Peer();
      peers.add(pc);
      return pc;
    },
  );
  Future<void> join({
    String local = 'a',
    String remote = 'b',
    bool includeRemote = true,
  }) async {
    service.supported = true;
    await service.begin('g', 'Spartan 1');
    final requestId = sent.last['data']['requestId'];
    await service.handlePacket({
      'type': 'group_call_joined',
      'data': {
        'requestId': requestId,
        'sessionId': local,
        'call': room(
          local: local,
          remote: remote,
          includeRemote: includeRemote,
        ),
      },
    });
  }

  Future<void> signal(
    Map<String, dynamic> signal, {
    String local = 'a',
    String remote = 'b',
  }) => service.handlePacket({
    'type': 'group_call_signal',
    'data': {
      'callId': 'call',
      'groupId': 'g',
      'from': 'B',
      'fromSession': remote,
      'toSession': local,
      'signal': signal,
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hasFonts = File('C:/Windows/Fonts/segoeui.ttf').existsSync();
  setUpAll(() async {
    if (!hasFonts) return;
    for (final font in {
      'GroupPreview': 'C:/Windows/Fonts/segoeui.ttf',
      'MaterialIcons': 'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key);
      loader.addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  test('room parser rejects duplicates, malformed and overcapacity', () {
    expect(GroupCallState.parse(room())!.members.length, 2);
    final videoRoom = room();
    (videoRoom['participants'] as List)[1]['videoEnabled'] = false;
    expect(GroupCallState.parse(videoRoom)!.members[1].videoEnabled, false);
    expect(GroupCallState.parse({}), isNull);
    final bad = room();
    bad['participants'] = [
      {'user': 'A', 'sessionId': 'x'},
      {'user': 'A', 'sessionId': 'y'},
    ];
    expect(GroupCallState.parse(bad), isNull);
    bad['participants'] = List.generate(
      5,
      (i) => {'user': '$i', 'sessionId': '$i'},
    );
    expect(GroupCallState.parse(bad), isNull);
    expect(GroupCallState.makesOffer('a', 'b'), true);
    expect(GroupCallState.makesOffer('b', 'a'), false);
  });
  test('old server cannot silently start an unsupported call', () async {
    final f = Fixture();
    await f.service.begin('g', 'Test');
    expect(f.service.hasCall, false);
    expect(f.sent, isEmpty);
    expect(f.service.notice, contains('сервер'));
  });
  test('outgoing SDP precedes ICE, remote ICE waits for answer', () async {
    final f = Fixture();
    await f.join();
    final signals = f.sent
        .where((x) => x['type'] == 'group_call_signal')
        .map((x) => x['data']['signal']['kind']);
    expect(signals, ['offer', 'ice']);
    await f.signal({
      'kind': 'ice',
      'candidate': {'candidate': 'remote', 'sdpMid': '0', 'sdpMLineIndex': 0},
    });
    expect(f.peers.single.events, ['local-offer']);
    await f.signal({'kind': 'answer', 'sdp': 'answer'});
    expect(f.peers.single.events, ['local-offer', 'remote-answer', 'ice']);
    await f.service.leave();
    expect(f.peers.single.closed, true);
    expect(f.stream.track.stopped, true);
  });
  test('answerer makes no competing offer; answer precedes ICE', () async {
    final f = Fixture();
    await f.join(local: 'z', remote: 'a');
    expect(f.sent.where((x) => x['type'] == 'group_call_signal'), isEmpty);
    await f.signal({'kind': 'offer', 'sdp': 'offer'}, local: 'z', remote: 'a');
    final kinds = f.sent
        .where((x) => x['type'] == 'group_call_signal')
        .map((x) => x['data']['signal']['kind']);
    expect(kinds, ['answer', 'ice']);
    await f.service.leave();
  });
  test('mute controls captured track, leaving releases mic', () async {
    final f = Fixture();
    await f.join(includeRemote: false);
    f.service.toggleMicrophone();
    expect(f.stream.track.enabled, false);
    expect(f.sent.last['data']['muted'], true);
    f.service.toggleMicrophone();
    expect(f.stream.track.enabled, true);
    await f.service.leave();
    expect(f.stream.released, true);
    expect(f.service.hasCall, false);
  });
  test(
    'viewer upgrade sends join and ignores the expected old-session exit',
    () async {
      final f = Fixture();
      f.service.supported = true;
      final watchingRoom = {
        'id': 'call',
        'groupId': 'g',
        'name': 'Spartan 1',
        'startedBy': 'B',
        'owner': 'B',
        'participants': [
          {'user': 'B', 'sessionId': 'host', 'role': 'host'},
          {'user': 'A', 'sessionId': 'viewer-a', 'role': 'viewer'},
        ],
      };
      f.service.rooms['g'] = GroupCallState.parse(watchingRoom)!;
      await f.service.watch('g', 'Spartan 1', 'call');
      final watchRequest = f.sent.last['data']['requestId'];
      await f.service.handlePacket({
        'type': 'group_call_watching',
        'data': {
          'requestId': watchRequest,
          'sessionId': 'viewer-a',
          'call': watchingRoom,
        },
      });
      f.service.requestJoin('g', 'Spartan 1', 'call');
      await f.service.handlePacket({
        'type': 'group_call_join_response',
        'data': {'groupId': 'g', 'callId': 'call', 'accepted': true},
      });
      expect(
        f.sent.map((item) => item['type']),
        contains('group_call_unwatch'),
      );
      expect(f.sent.map((item) => item['type']), contains('group_call_join'));
      await f.service.handlePacket({
        'type': 'group_call_left',
        'data': {
          'callId': 'call',
          'sessionId': 'viewer-a',
          'reason': 'Вы вышли из просмотра',
        },
      });
      expect(f.service.phase, GroupCallPhase.joining);
      final joinPacket = f.sent.lastWhere(
        (item) => item['type'] == 'group_call_join',
      );
      await f.service.handlePacket({
        'type': 'group_call_joined',
        'data': {
          'requestId': joinPacket['data']['requestId'],
          'sessionId': 'stage-a',
          'call': room(local: 'stage-a', remote: 'host'),
        },
      });
      expect(f.service.phase, GroupCallPhase.active);

      // The viewer-removal snapshot can be handled after group_call_joined.
      // It belongs to the old lease and must not evict the new stage session.
      await f.service.handlePacket({
        'type': 'group_call_state',
        'data': {
          'groupId': 'g',
          'call': {
            'id': 'call',
            'groupId': 'g',
            'name': 'Spartan 1',
            'startedBy': 'B',
            'owner': 'B',
            'participants': [
              {'user': 'B', 'sessionId': 'host', 'role': 'host'},
            ],
          },
        },
      });
      expect(f.service.phase, GroupCallPhase.active);
      expect(
        f.sent.where((item) => item['type'] == 'group_call_leave'),
        isEmpty,
      );

      // The first snapshot carrying the new lease confirms the transition.
      await f.service.handlePacket({
        'type': 'group_call_state',
        'data': {
          'groupId': 'g',
          'call': room(local: 'stage-a', remote: 'host'),
        },
      });
      expect(f.service.phase, GroupCallPhase.active);
      await f.service.leave();
    },
  );
  test(
    'leaving participant closes only its connection, not the room',
    () async {
      final f = Fixture();
      await f.join();
      await f.service.handlePacket({
        'type': 'group_call_state',
        'data': {'groupId': 'g', 'call': room(includeRemote: false)},
      });
      expect(f.peers.single.closed, true);
      expect(f.service.phase, GroupCallPhase.active);
      expect(f.stream.track.stopped, false);
      await f.service.leave();
    },
  );
  test(
    'rejoin uses a new peer; stale signaling and leave are ignored',
    () async {
      final f = Fixture();
      await f.join();
      await f.service.handlePacket({
        'type': 'group_call_state',
        'data': {'groupId': 'g', 'call': room(remote: 'c')},
      });
      expect(f.peers.length, 2);
      expect(f.peers.first.closed, true);
      await f.signal({'kind': 'answer', 'sdp': 'stale'});
      expect(f.peers.last.events, ['local-offer']);
      await f.service.handlePacket({
        'type': 'group_call_left',
        'data': {'callId': 'call', 'sessionId': 'old', 'reason': 'old'},
      });
      expect(f.service.phase, GroupCallPhase.active);
      await f.service.leave();
    },
  );
  test(
    'cancel while permission prompt is open never retains microphone',
    () async {
      final pending = Completer<MediaStream>();
      final stream = Stream();
      final sent = <String>[];
      final service = GroupCallService.forTesting(
        send: (type, data) => sent.add(type),
        user: 'A',
        media: () => pending.future,
        connection: () async => Peer(),
      );
      service.supported = true;
      final starting = service.begin('g', 'Test');
      await Future<void>.delayed(Duration.zero);
      await service.leave();
      pending.complete(stream);
      await starting;
      expect(stream.track.stopped, true);
      expect(stream.released, true);
      expect(sent, isEmpty);
    },
  );
  test(
    'late join acknowledgment after cancellation relinquishes its lease',
    () async {
      final f = Fixture();
      f.service.supported = true;
      await f.service.begin('g', 'Test');
      final requestId = f.sent.last['data']['requestId'];
      await f.service.leave();
      await f.service.handlePacket({
        'type': 'group_call_joined',
        'data': {'requestId': requestId, 'sessionId': 'a', 'call': room()},
      });
      expect(f.service.hasCall, false);
      expect(f.sent.last['type'], 'group_call_leave');
      expect(f.sent.last['data']['sessionId'], 'a');
    },
  );
  test(
    'disconnect releases room resources and disables unsupported stale state',
    () async {
      final f = Fixture();
      await f.join();
      await f.service.handlePacket({'type': 'disconnected', 'data': {}});
      expect(f.service.hasCall, false);
      expect(f.service.supported, false);
      expect(f.stream.track.stopped, true);
    },
  );
  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('group controls remain accessible at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = Fixture();
      f.service.groupName = 'Spartan 1';
      f.service.phase = GroupCallPhase.active;
      f.service.current = GroupCallState.parse(room());
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SpartanPalette.blueGoldTheme.copyWith(
            textTheme: SpartanPalette.blueGoldTheme.textTheme.apply(
              fontFamily: 'GroupPreview',
            ),
          ),
          home: GroupCallScreen(service: f.service),
        ),
      );
      expect(
        find.byKey(const ValueKey('group-leave')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-mic')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (size.width == 320 && hasFonts)
        await expectLater(
          find.byType(GroupCallScreen),
          matchesGoldenFile('goldens/group_voice_v1.png'),
        );
      await tester.pumpWidget(const SizedBox.shrink());
      await f.service.leave();
    });
  }
}
