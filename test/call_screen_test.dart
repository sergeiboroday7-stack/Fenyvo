import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/main.dart';
import 'package:spartan_chat_final/screens/call_screen.dart';
import 'package:spartan_chat_final/services/call_service.dart';
import 'package:spartan_chat_final/services/call_result.dart';
import 'package:spartan_chat_final/services/system_call_service.dart';

void main() {
  final service = CallService.instance;

  setUp(() async {
    await service.hangUp();
  });

  tearDown(() async {
    await service.hangUp();
  });

  testWidgets(
    'remote cancellation produces a missed result, not local decline',
    (tester) async {
      service.initialize();
      service.phase = CallPhase.incoming;
      service.callId = 'remote-cancel-test';
      service.peerUser = 'Test peer';
      service.isIncoming = true;
      service.outcome = null;
      SystemCallService.instance.onRemoteCancel!('remote-cancel-test');
      await tester.pump();
      expect(service.lastFinishedCall?.outcome, CallOutcome.missed);
      expect(service.statusText, 'Пропущенный звонок');
      await tester.pump(const Duration(seconds: 2));
      expect(service.phase, CallPhase.idle);
      expect(service.lastFinishedCall?.outcome, CallOutcome.missed);
    },
  );

  test('native hang-up after connection is completed, not declined', () async {
    service.initialize();
    service.phase = CallPhase.active;
    service.callId = 'connected-native-end';
    service.peerUser = 'Test peer';
    service.isIncoming = true;
    service.outcome = null;
    service.clock.connect();
    SystemCallService.instance.onEnd!('connected-native-end');
    await Future<void>.delayed(Duration.zero);
    expect(service.lastFinishedCall?.outcome, CallOutcome.completed);
    expect(service.lastFinishedCall?.id, 'connected-native-end');
  });

  testWidgets('incoming audio call can be rejected without opening media', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    service.phase = CallPhase.incoming;
    service.callId = 'test-incoming';
    service.peerUser = 'Test peer';
    service.statusText = 'Входящий аудиозвонок';
    await tester.pumpWidget(const MaterialApp(home: CallScreen()));
    expect(find.text('Принять'), findsOneWidget);
    expect(find.text('Отклонить'), findsOneWidget);
    expect(service.localRenderer.srcObject, isNull);
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    expect(service.phase, CallPhase.idle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('video controls fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    service.phase = CallPhase.outgoing;
    service.callId = 'test-video';
    service.peerUser = 'Test peer';
    service.isVideo = true;
    service.cameraEnabled = true;
    await tester.pumpWidget(const MaterialApp(home: CallScreen()));
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
    expect(find.text('Завершить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global call route opens and closes on hangup', (tester) async {
    service.phase = CallPhase.incoming;
    service.callId = 'test-route';
    service.peerUser = 'Test peer';
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: spartanNavigatorKey,
        builder: (context, child) => CallNavigationHost(child: child!),
        home: const Scaffold(body: Text('Chats')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CallScreen), findsOneWidget);
    await service.hangUp();
    await tester.pumpAndSettle();
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('Chats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
