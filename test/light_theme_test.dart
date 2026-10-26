// Platform interfaces are transitive test-only helpers; no new app dependency.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fenyvo/services/saved_messages_service.dart';
import 'package:fenyvo/screens/saved_messages_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fenyvo/screens/auth_screen.dart';
import 'package:fenyvo/screens/chat_screen.dart';
import 'package:fenyvo/screens/chat_list_screen.dart';
import 'package:fenyvo/screens/group_chat_screen.dart';
import 'package:fenyvo/settings_screen.dart';
import 'package:fenyvo/services/storage_service.dart';
import 'package:fenyvo/services/socket_service.dart';
import 'package:fenyvo/services/app_language_service.dart';
import 'package:fenyvo/theme/fenyvo_theme.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late HttpServer server;
  final clients = <WebSocket>[];
  final sent = <Map<String, dynamic>>[];
  final hasGoldenFonts = File('C:/Windows/Fonts/segoeui.ttf').existsSync();
  final demo = <Map<String, dynamic>>[
    {
      'id': 'light1',
      'from': 'Sparta',
      'to': 'Acer',
      'text': 'Привет! Как тебе новый дизайн?',
      'time': '2026-09-04T12:00:00',
      'messageType': 'text',
      'status': 'read',
    },
    {
      'id': 'light2',
      'from': 'Acer',
      'to': 'Sparta',
      'text': 'Синий с золотом. Мне нравится!',
      'time': '2026-09-04T12:01:00',
      'messageType': 'text',
      'status': 'read',
    },
    {
      'id': 'light3',
      'from': 'Sparta',
      'to': 'Acer',
      'text': 'Давай проверим фото, голосовые и звонки.',
      'time': '2026-09-04T12:02:00',
      'messageType': 'text',
      'status': 'read',
    },
    {
      'id': 'light4',
      'from': 'Acer',
      'to': 'Sparta',
      'text': 'На связи',
      'time': '2026-09-04T12:03:00',
      'messageType': 'text',
      'status': 'read',
    },
  ];
  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('spartan_light_test_');
    PathProviderPlatform.instance = _TestPaths(sandbox.path);
    SharedPreferences.setMockInitialValues({
      'chat_background': 'preserved-wallpaper.jpg',
      'spartan_group_pins_light-group': ['light1'],
    });
    await AppLanguageService.instance.select('ru');
    demo.first['isPinned'] = true;
    final now = DateTime.now();
    for (var i = 0; i < demo.length; i++) {
      demo[i]['time'] = DateTime(
        now.year,
        now.month,
        now.day,
        12,
        i,
      ).toIso8601String();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fenyvo/screen_security'),
          (call) async {
            if (call.method != 'setSecure') {
              throw MissingPluginException('Unexpected screen security method');
            }
            return null;
          },
        );
    await StorageService.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'com.llfbandit.record/messages',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (call) async => null,
          );
        }
        return null;
      },
    );
    for (final font in {
      'PreviewText': 'C:/Windows/Fonts/segoeui.ttf',
      'Segoe UI Emoji': 'C:/Windows/Fonts/seguiemj.ttf',
      'MaterialIcons': 'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      if (File(font.value).existsSync()) {
        final loader = FontLoader(font.key)
          ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    }
    // Loopback fixture only: never connects to the user's live chat server.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.transform(WebSocketTransformer()).listen((client) {
      clients.add(client);
      client.listen((raw) {
        final event = Map<String, dynamic>.from(jsonDecode(raw as String));
        sent.add(event);
        if (event['type'] == 'get_groups') {
          client.add(
            jsonEncode({
              'type': 'groups',
              'data': {
                'groups': [
                  {
                    'id': 'light-group',
                    'name': 'Fenyvo 1',
                    'members': ['Acer', 'Sparta', 'Alla'],
                  },
                ],
              },
            }),
          );
        }
        if (event['type'] == 'get_group_messages') {
          client.add(
            jsonEncode({
              'type': 'group_messages',
              'data': {
                'groupId': 'light-group',
                'hasMore': false,
                'messages': demo,
              },
            }),
          );
        }
        if (event['type'] == 'group_message') {
          client.add(
            jsonEncode({
              'type': 'group_message',
              'data': {
                ...Map<String, dynamic>.from(event['data'] as Map),
                'id': 'sent-test',
                'from': 'Acer',
                'time': '2026-09-04T12:04:00',
              },
            }),
          );
        }
      });
    });
    await SocketService.instance.connect('ws://127.0.0.1:${server.port}');
    SocketService.instance.currentUser = 'Acer';
    StorageService.saveMessages('Acer', 'Sparta', demo);
    StorageService.saveMessages('Acer', 'Alla', [
      {
        'id': 'light5',
        'from': 'Alla',
        'to': 'Acer',
        'text': 'Привет!',
        'time': '2026-09-04T11:00:00',
        'messageType': 'text',
      },
    ]);
  });
  tearDownAll(() async {
    print('Close test sockets');
    await Future.wait([
      SocketService.instance.disconnect(),
      for (final client in clients) client.close(),
    ]).timeout(const Duration(seconds: 5));
    print('Close test server');
    await server.close(force: true).timeout(const Duration(seconds: 5));
    print('Close isolated test storage');
    await Hive.close().timeout(const Duration(seconds: 5));
    // The only recursively removed directory is the exact temp test sandbox.
    await sandbox.delete(recursive: true);
  });

  test(
    'blue gold palette meets contrast and preserves wallpaper opt-in',
    () async {
      expect(FenyvoPalette.lightTheme.brightness, Brightness.dark);
      expect(
        (FenyvoPalette.ink.computeLuminance() + .05) /
            (FenyvoPalette.canvas.computeLuminance() + .05),
        greaterThan(10),
      );
      expect(
        (FenyvoPalette.ink.computeLuminance() + .05) /
            (FenyvoPalette.blueDeep.computeLuminance() + .05),
        greaterThan(4.5),
      );
      expect(await StorageService.getLightBackground(), isNull);
      expect(await StorageService.getBackground(), 'preserved-wallpaper.jpg');
      await StorageService.setLightWallpaperEnabled(true);
      expect(
        await StorageService.getLightBackground(),
        'preserved-wallpaper.jpg',
      );
      await StorageService.setLightWallpaperEnabled(false);
    },
  );

  Future<void> pumpScreen(WidgetTester tester, Widget child, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: FenyvoPalette.lightTheme.copyWith(
          textTheme: FenyvoPalette.lightTheme.textTheme.apply(
            fontFamily: 'PreviewText',
          ),
        ),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('light-preview'),
          child: FenyvoLightFrame(child: child!),
        ),
        home: child,
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Hive writes initiated by widgets resume in the widget's FakeAsync zone.
    // Keep pumping that zone until the disk queue drains before leaving it.
    var flushed = false;
    Object? flushError;
    unawaited(
      Future.wait([
        for (final name in [
          'chat_messages',
          'avatars',
          'unread_messages',
          'spartan_saved_messages',
          'spartan_call_history',
        ])
          Hive.box(name).flush(),
      ]).then(
        (_) {
          flushed = true;
        },
        onError: (Object e) {
          flushError = e;
          flushed = true;
        },
      ),
    );
    for (var i = 0; i < 100 && !flushed; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }
    expect(flushError, isNull);
    expect(
      flushed,
      isTrue,
      reason: 'Isolated Hive writes must finish before the test zone closes',
    );
  }

  // Keep real Hive's serialized I/O chain in one FakeAsync zone across screens.
  testWidgets('BLUE GOLD navigation, emoji, saved messages and real screens', (
    tester,
  ) async {
    try {
      for (final variant in [
        'private',
        'windows',
        'list',
        'group',
        'media',
        'saved',
        'settings',
        'auth',
      ]) {
        if (variant == 'media') {
          final imageFile = File('assets/images/chat_list_bg.png').absolute;
          await tester.runAsync(
            () => precacheImage(
              FileImage(imageFile),
              tester.element(find.byType(SizedBox).first),
            ),
          );
          StorageService.saveMessages('Acer', 'Media', [
            {
              'id': 'media-voice',
              'from': 'Media',
              'to': 'Acer',
              'messageType': 'voice',
              'text': 'Голосовое сообщение',
              'voiceDurationMs': 8000,
              'time': demo[0]['time'],
              'localMediaPath': File('assets/sounds/spartan_phoenix_call.wav')
                  .absolute
                  .path,
            },
            {
              'id': 'media-image',
              'from': 'Acer',
              'to': 'Media',
              'messageType': 'image',
              'text': 'Фото',
              'localMediaPath': File('assets/images/chat_list_bg.png')
                  .absolute
                  .path,
              'time': demo[1]['time'],
            },
            {
              'id': 'media-file',
              'from': 'Media',
              'to': 'Acer',
              'messageType': 'file',
              'text': 'План.pdf',
              'fileName': 'План.pdf',
              'fileSize': 2048,
              'time': demo[2]['time'],
            },
          ]);
        }
        final Widget screen = switch (variant) {
          'private' => const ChatScreen(targetUser: 'Sparta'),
          'media' => const ChatScreen(targetUser: 'Media'),
          'windows' => const ChatListScreen(),
          'list' => const ChatListScreen(),
          'saved' => const SavedMessagesScreen(owner: 'Acer'),
          'group' => const GroupChatScreen(
            group: {
              'id': 'light-group',
              'name': 'Fenyvo 1',
              'members': ['Acer', 'Sparta', 'Alla'],
            },
          ),
          'settings' => SettingsScreen(username: 'Acer', onLogout: () {}),
          _ => const AuthScreen(),
        };
        await pumpScreen(
          tester,
          screen,
          variant == 'windows' ? const Size(1280, 800) : const Size(390, 844),
        );
        if (variant == 'windows') {
          await tester.tap(find.text('Sparta').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
        if (variant == 'private' || variant == 'group') {
          expect(find.text('Синий с золотом. Мне нравится!'), findsOneWidget);
          expect(find.byType(TextField), findsOneWidget);
        }
        if (variant == 'media') {
          expect(find.byType(Image), findsOneWidget);
          expect(tester.getSize(find.byType(Image)).height, greaterThan(100));
          expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (hasGoldenFonts)
          await expectLater(
            find.byKey(const ValueKey('light-preview')),
            matchesGoldenFile('goldens/blue_gold_$variant.png'),
          );
        if (variant == 'private') {
          final input = find.byKey(const ValueKey('private-composer'));
          await tester.enterText(input, 'Привет друг');
          final controller = tester.widget<TextField>(input).controller!;
          controller.selection = const TextSelection.collapsed(offset: 6);
          final beforeSend = sent.where((e) => e['type'] == 'message').length;
          await tester.tap(find.byIcon(Icons.emoji_emotions_outlined).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('😊').first);
          await tester.pump();
          // Emoji must be below, not over, the live draft and send button.
          final emojiPanel = find.byKey(const ValueKey('composer-emoji-panel'));
          expect(
            tester.getRect(input).bottom,
            lessThanOrEqualTo(tester.getRect(emojiPanel).top),
          );
          expect(input.hitTestable(), findsOneWidget);
          expect(find.byIcon(Icons.send_rounded).hitTestable(), findsOneWidget);
          expect(controller.text, 'Привет😊 друг');
          expect(sent.where((e) => e['type'] == 'message').length, beforeSend);
          if (hasGoldenFonts)
            await expectLater(
              find.byKey(const ValueKey('light-preview')),
              matchesGoldenFile('goldens/blue_gold_emoji.png'),
            );
          await tester.tap(find.byTooltip('Закрыть смайлики'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.enterText(input, '');
          await tester.pump();
          expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
          await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          for (final title in ['Фото', 'Видео', 'Файл']) {
            expect(find.text(title), findsOneWidget);
          }
          if (hasGoldenFonts)
            await expectLater(
              find.byKey(const ValueKey('light-preview')),
              matchesGoldenFile('goldens/blue_gold_attachments.png'),
            );
          Navigator.of(tester.element(find.text('Фото'))).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
        if (variant == 'group') {
          await tester.enterText(find.byType(TextField), 'Тест отправки');
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byIcon(Icons.send_rounded), findsOneWidget);
          await tester.tap(find.byIcon(Icons.send_rounded));
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
        }
        if (variant == 'windows') {
          final composer = find.byKey(const ValueKey('private-composer'));
          await tester.enterText(composer, 'Черновик без отправки');
          await tester.tap(find.byKey(const ValueKey('nav-1')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.byKey(const ValueKey('nav-0')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            tester.widget<TextField>(composer).controller!.text,
            'Черновик без отправки',
          );
          await tester.enterText(composer, '');
          await tester.pump();
        }
        if (variant == 'private' || variant == 'group') {
          await tester.longPress(find.text('На связи').last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('Сохранить'), findsOneWidget);
          await tester.tap(find.text('Сохранить'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          final origin = variant == 'private' ? 'Sparta' : 'Группа: Fenyvo 1';
          for (
            var i = 0;
            i < 100 &&
                !SavedMessagesService.items('Acer')
                    .any((e) => e['origin'] == origin);
            i++
          ) {
            await tester.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(
            SavedMessagesService.items('Acer')
                .any((e) => e['origin'] == origin && e['text'] == 'На связи'),
            isTrue,
          );
          expect(find.text('На связи'), findsOneWidget);
          ScaffoldMessenger.of(tester.element(find.byType(TextField).first))
              .clearSnackBars();
          await tester.pump(const Duration(seconds: 1));
        }
        if (variant == 'list') {
          expect(
            find.byKey(const ValueKey('fenyvo-mobile-command-dock')),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const ValueKey('contact-search')),
            'aLlA',
          );
          await tester.pump();
          expect(find.text('Alla'), findsOneWidget);
          expect(find.text('Sparta'), findsNothing);
          await tester.tap(find.byTooltip('Очистить поиск'));
          await tester.tap(find.byKey(const ValueKey('chat-filter-2')));
          await tester.pump();
          expect(find.text('Alla'), findsNothing);
          expect(find.text('Сохранённое'), findsNothing);
          expect(find.text('Fenyvo 1'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('chat-filter-1')));
          await tester.pump();
          expect(find.text('Alla'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('mobile-command-1')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('Позвонить контакту'), findsOneWidget);
          if (hasGoldenFonts)
            await expectLater(
              find.byKey(const ValueKey('light-preview')),
              matchesGoldenFile('goldens/blue_gold_calls.png'),
            );
          await tester.tap(find.byKey(const ValueKey('mobile-command-2')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(SettingsScreen), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('mobile-command-0')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Сохранённое'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(SavedMessagesScreen), findsOneWidget);
          expect(find.text('Только на этом устройстве'), findsOneWidget);
          Navigator.of(tester.element(find.byType(SavedMessagesScreen))).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
        if (variant == 'saved') {
          await tester.enterText(find.byType(TextField), 'Моя важная заметка');
          await tester.pump();
          final before = sent.where((e) => e['type'] == 'message').length;
          await tester.tap(find.byTooltip('Сохранить заметку'));
          for (
            var i = 0;
            i < 100 &&
                tester
                    .widget<TextField>(find.byType(TextField))
                    .controller!
                    .text
                    .isNotEmpty;
            i++
          ) {
            await tester.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('Моя важная заметка'), findsOneWidget);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          expect(sent.where((e) => e['type'] == 'message').length, before);
          if (hasGoldenFonts)
            await expectLater(
              find.byKey(const ValueKey('light-preview')),
              matchesGoldenFile('goldens/blue_gold_saved_note.png'),
            );
        }
        expect(tester.takeException(), isNull);
        await finish(tester);
      }
    } finally {
      await finish(tester);
      var closed = false;
      unawaited(Hive.close().then((_) => closed = true));
      for (var i = 0; i < 100 && !closed; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      expect(closed, isTrue);
    }
  });

  testWidgets('frame never steals input and disabling it preserves state', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, value, _) => FenyvoLightFrame(
            enabled: value,
            child: Scaffold(body: TextField(controller: controller)),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Остаётся при звонке');
    final inputState = tester.state(find.byType(EditableText));
    enabled.value = false;
    await tester.pump();
    expect(controller.text, 'Остаётся при звонке');
    expect(
      identical(inputState, tester.state(find.byType(EditableText))),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    enabled.dispose();
    controller.dispose();
  });
}
