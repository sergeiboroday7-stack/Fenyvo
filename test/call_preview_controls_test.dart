import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:fenyvo/screens/call_screen.dart';
import 'package:fenyvo/services/call_service.dart';
import 'package:fenyvo/services/app_language_service.dart';

class _PreviewStream implements MediaStream {
  @override
  String get id => 'preview-stream';
  @override
  String get ownerTag => 'local';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('camera-off preview cannot cover landscape hang-up control', (
    tester,
  ) async {
    AppLanguageService.instance.code.value = 'ru';
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Method'),
      (call) async {
        if (call.method == 'createVideoRenderer') return {'textureId': 77};
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC/Texture77'),
      (_) async => null,
    );
    final service = CallService.instance;
    await service.localRenderer.initialize();
    service.localRenderer.srcObject = _PreviewStream();
    service.callId = 'preview-call';
    service.peerUser = 'Test peer';
    service.phase = CallPhase.active;
    service.isVideo = true;
    service.cameraEnabled = false;
    service.microphoneEnabled = false;
    service.clock.connected = true;
    service.statusText = 'Соединено';
    await tester.pumpWidget(const MaterialApp(home: CallScreen()));
    await tester.pump();
    expect(find.text('Камера\nвыключена'), findsOneWidget);
    expect(find.byType(RTCVideoView), findsNothing);
    expect(tester.takeException(), isNull);
    // This point overlaps the local preview's rectangle and the end-call icon.
    final endIcon = tester.getCenter(find.byIcon(Icons.call_end_rounded));
    await tester.tapAt(endIcon + const Offset(22, 0));
    await tester.pumpAndSettle();
    expect(service.phase, CallPhase.idle);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => service.localRenderer.dispose());
  });
}
