import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/screens/call_screen.dart';
import 'package:spartan_chat_final/services/call_service.dart';

void main() {
  setUpAll(() async {
    if (!File('C:/Windows/Fonts/segoeui.ttf').existsSync() ||
        !File(
          'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).existsSync())
      return;
    final text = FontLoader('PreviewText');
    text.addFont(
      File('C:/Windows/Fonts/segoeui.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
    await text.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
    await icons.load();
  });
  for (final variant in [
    'incoming',
    'connected',
    'muted_video',
    'muted_desktop',
  ]) {
    testWidgets(
      'call portrait $variant',
      (tester) async {
        final incoming = variant == 'incoming';
        final muted = variant.startsWith('muted');
        tester.view.physicalSize = variant == 'muted_desktop'
            ? const Size(1280, 720)
            : const Size(390, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = CallService.instance;
        service.callId = 'preview';
        service.peerUser = 'Sparta';
        service.phase = incoming ? CallPhase.incoming : CallPhase.active;
        service.isVideo = muted;
        service.microphoneEnabled = !muted;
        service.cameraEnabled = !muted;
        service.statusText = incoming ? 'Входящий аудиозвонок' : 'Соединено';
        service.avatarBytes = File('assets/images/chat_list_bg.png')
            .readAsBytesSync();
        service.clock.connected = !incoming;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'PreviewText'),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: RepaintBoundary(
                key: const ValueKey('preview'),
                child: const CallScreen(),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(service.avatarBytes!),
            tester.element(find.byType(CallScreen)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('call-duration')),
          incoming ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('preview')),
          matchesGoldenFile('goldens/call_$variant.png'),
        );
        await service.hangUp();
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip:
          !File('C:/Windows/Fonts/segoeui.ttf').existsSync() ||
          !File(
            'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).existsSync(),
    );
  }
}
