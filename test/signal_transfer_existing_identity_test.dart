import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal/libsignal.dart';
import 'package:spartan_chat_final/services/crypto/signal_secure_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LibSignal.init();
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('missing transfer identity is not regenerated or written', () async {
    await expectLater(
      SignalSecureStore('Alice').readExistingIdentityForTransfer(),
      throwsStateError,
    );
    expect(await const FlutterSecureStorage().readAll(), isEmpty);
  });
  test('existing identity is read only and isolated by account', () async {
    final pair = IdentityKeyPair.generate();
    final stored = {
      'spartan_signal_v2.' +
          base64Url.encode(utf8.encode('Alice')) +
          '.identity.pair': base64Encode(
        pair.serialize(),
      ),
    };
    FlutterSecureStorage.setMockInitialValues(stored);
    final loaded = await SignalSecureStore('Alice')
        .readExistingIdentityForTransfer();
    try {
      expect(loaded.publicKey, pair.publicKey);
      await expectLater(
        SignalSecureStore('Bob').readExistingIdentityForTransfer(),
        throwsStateError,
      );
      expect(await const FlutterSecureStorage().readAll(), stored);
    } finally {
      loaded.dispose();
      pair.dispose();
    }
  });
}
