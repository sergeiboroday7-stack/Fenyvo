import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fenyvo/services/e2ee_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('E2EE enabled on new installation', () async {
    expect(await E2eeSettingsService.instance.isEnabled(), isTrue);
  });

  test('legacy false value does not disable E2EE', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('signal_e2ee_enabled_v2', false);

    expect(await E2eeSettingsService.instance.isEnabled(), isTrue);

    await E2eeSettingsService.instance.setEnabled(false);

    expect(await E2eeSettingsService.instance.isEnabled(), isTrue);
    expect(preferences.getBool('signal_e2ee_enabled_v2'), isTrue);
  });

  test('peer settings remain independent', () async {
    await E2eeSettingsService.instance.setPeerActive(
      'alice',
      'bob',
      true,
    );

    expect(
      await E2eeSettingsService.instance.activePeers('alice'),
      contains('bob'),
    );
  });
}