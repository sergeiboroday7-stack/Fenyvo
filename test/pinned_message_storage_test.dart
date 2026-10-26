// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:fenyvo/services/storage_service.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;

  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('spartan_pin_test_');
    PathProviderPlatform.instance = _TestPaths(sandbox.path);
    await StorageService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await sandbox.delete(recursive: true);
  });

  test(
    'offline pin state is written to and removed from stored chat history',
    () {
      StorageService.saveMessages('Sparta', 'Alla', [
        {
          'id': 'message-1',
          'from': 'Alla',
          'to': 'Sparta',
          'text': 'Защищённый текст остаётся локальным',
        },
      ]);

      expect(
        StorageService.updateMessagePinnedState(
          'Sparta',
          'Alla',
          'message-1',
          true,
        ),
        isTrue,
      );
      expect(
        StorageService.getMessages('Sparta', 'Alla').single['isPinned'],
        isTrue,
      );

      expect(
        StorageService.updateMessagePinnedState(
          'Sparta',
          'Alla',
          'message-1',
          false,
        ),
        isTrue,
      );
      expect(
        StorageService.getMessages('Sparta', 'Alla').single['isPinned'],
        isFalse,
      );
    },
  );
}
