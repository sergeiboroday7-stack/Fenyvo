import 'package:fenyvo/services/app_language_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/theme/fenyvo_theme.dart';
import 'package:fenyvo/widgets/my_fenyvo_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLanguageService.instance.code.value = 'ru';
  testWidgets('My Fenyvo keeps its identity and opens every quick action', (
    tester,
  ) async {
    final opened = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: FenyvoPalette.blueGoldTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyFenyvoDashboard(
              username: 'SpartaFenix',
              avatar: const CircleAvatar(child: Text('S')),
              status: 'В сети',
              about: 'Всегда открыт к новым идеям',
              region: 'Киев',
              phone: '+380 63 000 00 00',
              birthDate: '1989-10-05',
              uploadingAvatar: false,
              onAvatarTap: () => opened.add('avatar'),
              onEditProfile: () => opened.add('profile'),
              onOpenContact: () => opened.add('contact'),
              onOpenAppearance: () => opened.add('appearance'),
              onOpenPrivacy: () => opened.add('privacy'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('МОЙ FENYVO'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsNWidgets(2));
    expect(find.text('SpartaFenix'), findsOneWidget);
    expect(find.text('Всегда открыт к новым идеям'), findsOneWidget);
    expect(find.text('+380 63 000 00 00'), findsOneWidget);
    expect(find.text('05.10.1989'), findsOneWidget);

    await tester.ensureVisible(find.text('Профиль'));
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Редактировать профиль'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Мой контакт и QR-код'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Внешний вид'));
    await tester.tap(find.text('Внешний вид'));
    await tester.pump();

    await tester.ensureVisible(find.text('Приватность'));
    await tester.tap(find.text('Приватность'));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const ValueKey('my-fenyvo-avatar')));
    await tester.tap(find.byKey(const ValueKey('my-fenyvo-avatar')));

    expect(
      opened,
      containsAll(<String>[
        'profile',
        'contact',
        'appearance',
        'privacy',
        'avatar',
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Fenyvo fits a narrow phone without horizontal overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: FenyvoPalette.blueGoldTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyFenyvoDashboard(
              username: 'ОченьДлинноеИмяПользователяFenyvo',
              avatar: const CircleAvatar(child: Text('F')),
              status: 'Всегда на связи и открыт к общению',
              about: 'Собственное пространство Fenyvo без копирования других мессенджеров.',
              region: 'Очень длинное название региона',
              phone: '',
              birthDate: '',
              uploadingAvatar: true,
              onAvatarTap: () {},
              onEditProfile: () {},
              onOpenContact: () {},
              onOpenAppearance: () {},
              onOpenPrivacy: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('my-fenyvo-hero')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
