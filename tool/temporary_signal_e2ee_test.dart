import 'package:flutter/material.dart';
import 'package:spartan_chat_final/services/crypto/temporary_signal_e2ee_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _E2eeHarness());
}

class _E2eeHarness extends StatefulWidget {
  const _E2eeHarness();

  @override
  State<_E2eeHarness> createState() => _E2eeHarnessState();
}

class _E2eeHarnessState extends State<_E2eeHarness> {
  String status = 'Running temporary Signal E2EE test...';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runTest();
    });
  }

  Future<void> _runTest() async {
    try {
      const sessionId =
          'ffe5ad4f63e9567913080e38e6fc6b472f8e4ed8cad8d75d';

      final owner = TemporarySignalE2eeService();
      final guest = TemporarySignalE2eeService();

      final ownerId =
          TemporarySignalE2eeService.identityForSession(
        sessionId,
        'owner',
      );

      final guestId =
          TemporarySignalE2eeService.identityForSession(
        sessionId,
        'guest',
      );

      await owner.initializeForIdentity(ownerId);
      await guest.initializeForIdentity(guestId);

      debugPrint('PASS 1: temporary identities initialized');

      final publicBundle = await owner.createPublicBundle();

      final preKeys =
          (publicBundle['preKeys'] as List)
              .cast<Map<String, dynamic>>();

      final kyberPreKeys =
          (publicBundle['kyberPreKeys'] as List)
              .cast<Map<String, dynamic>>();

      if (preKeys.isEmpty || kyberPreKeys.isEmpty) {
        throw StateError('Prekey bundle is empty');
      }

      final remoteBundle = <String, dynamic>{
        'version': publicBundle['version'],
        'protocol': publicBundle['protocol'],
        'deviceId': publicBundle['deviceId'],
        'registrationId': publicBundle['registrationId'],
        'identityKey': publicBundle['identityKey'],
        'signedPreKey': publicBundle['signedPreKey'],
        'preKey': preKeys.first,
        'kyberPreKey': kyberPreKeys.first,
      };

      debugPrint('PASS 2: owner public bundle created');

      await guest.processRemoteBundle(
        ownerId,
        remoteBundle,
      );

      debugPrint('PASS 3: guest processed owner bundle');

      final payload = <String, dynamic>{
        'sessionId': sessionId,
        'messageId': 'dart_e2ee_test_001',
        'time': 1,
        'text': 'temporary e2ee works',
      };

      final encrypted = await guest.encrypt(
        ownerId,
        payload,
      );

      debugPrint('PASS 4: guest encrypted payload');

      final decrypted = await owner.decrypt(
        guestId,
        encrypted,
      );

      if (decrypted['sessionId'] != sessionId) {
        throw StateError('sessionId mismatch');
      }

      if (decrypted['messageId'] != 'dart_e2ee_test_001') {
        throw StateError('messageId mismatch');
      }

      if (decrypted['text'] != 'temporary e2ee works') {
        throw StateError('text mismatch');
      }

      debugPrint('PASS 5: owner decrypted payload');
      debugPrint('TEMPORARY SIGNAL E2EE TEST: PASSED');

      if (mounted) {
        setState(() {
          status = 'TEMPORARY SIGNAL E2EE TEST: PASSED';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('TEMPORARY SIGNAL E2EE TEST: FAILED');
      debugPrint('$error');
      debugPrint('$stackTrace');

      if (mounted) {
        setState(() {
          status = 'FAILED: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SelectableText(status),
        ),
      ),
    );
  }
}
