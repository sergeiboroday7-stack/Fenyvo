import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/pulse_service.dart';

Map<String, dynamic> pulsePacket({
  String id = 'pulse-1',
  String from = 'Alice',
  String to = 'Bob',
  bool video = true,
  String state = 'pending',
  int? startsAt,
}) {
  return <String, dynamic>{
    'id': id,
    'from': from,
    'to': to,
    'video': video,
    'createdAt': 1000,
    'expiresAt': 3601000,
    'state': state,
    'startsAt': startsAt,
  };
}

void main() {
  test('SpartanPulse validates packets and calculates its window', () {
    expect(SpartanPulse.parse(null), isNull);
    expect(SpartanPulse.parse(<String, dynamic>{'id': 'incomplete'}), isNull);

    final pulse = SpartanPulse.parse(pulsePacket());
    expect(pulse, isNotNull);
    expect(pulse!.peerFor('Alice'), 'Bob');
    expect(pulse.peerFor('Bob'), 'Alice');
    expect(pulse.windowMinutes, 60);
  });

  test('request and acceptance send only the Pulse control packets', () {
    final sent = <Map<String, dynamic>>[];
    final service = PulseService.forTesting(
      send: (type, data) =>
          sent.add(<String, dynamic>{'type': type, 'data': data}),
      currentUser: () => 'Bob',
      callBusy: () => false,
      startCall: (_, _) async {},
      now: () => 1234,
    );

    service.request(peer: 'Alice', video: false, windowMinutes: 15);
    expect(sent.single['type'], 'pulse_request');
    expect((sent.single['data'] as Map<String, dynamic>)['to'], 'Alice');
    expect((sent.single['data'] as Map<String, dynamic>)['video'], false);

    service.handleMessage(<String, dynamic>{
      'type': 'pulse_invite',
      'data': <String, dynamic>{'pulse': pulsePacket()},
    });
    expect(service.phase, SpartanPulsePhase.incoming);
    expect(service.activeFor('Alice'), isNotNull);

    service.accept();
    expect(sent.last['type'], 'pulse_accept');
    expect(service.phase, SpartanPulsePhase.outgoing);
    service.dispose();
  });

  test(
    'only the initiator starts the existing private call after a match',
    () async {
      final calls = <({String peer, bool video})>[];
      final service = PulseService.forTesting(
        send: (_, _) {},
        currentUser: () => 'Alice',
        callBusy: () => false,
        startCall: (peer, video) async => calls.add((peer: peer, video: video)),
        now: () => 5000,
      );

      service.handleMessage(<String, dynamic>{
        'type': 'pulse_match',
        'data': <String, dynamic>{
          'pulse': pulsePacket(state: 'matched', startsAt: 5000),
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(calls, [(peer: 'Bob', video: true)]);
      expect(service.phase, SpartanPulsePhase.matched);
      service.dispose();
    },
  );

  test(
    'recipient waits for the initiator instead of creating a second call',
    () async {
      var callCount = 0;
      final service = PulseService.forTesting(
        send: (_, _) {},
        currentUser: () => 'Bob',
        callBusy: () => false,
        startCall: (_, _) async => callCount++,
        now: () => 5000,
      );

      service.handleMessage(<String, dynamic>{
        'type': 'pulse_match',
        'data': <String, dynamic>{
          'pulse': pulsePacket(state: 'matched', startsAt: 5000),
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(callCount, 0);
      service.dispose();
    },
  );
}
