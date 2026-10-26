import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/incoming_call_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('spartan_chat/alert_test');
  final calls = <MethodCall>[];
  late IncomingCallAlertService service;

  setUp(() {
    calls.clear();
    service = IncomingCallAlertService.forTesting(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('one incoming call starts only once and stop is idempotent', () async {
    await service.start('one');
    await service.start('one');
    await service.stop();
    await service.stop();
    expect(calls.map((call) => call.method), ['start', 'stop']);
    expect(calls.every((call) => call.arguments['callId'] == 'one'), isTrue);
  });

  test('a quick answer stops even while platform start is pending', () async {
    final pending = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'start') await pending.future;
          return null;
        });
    final start = service.start('fast-answer');
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    pending.complete();
    await start;
    expect(calls.map((call) => call.method), ['start', 'stop']);
    expect(calls.last.arguments['callId'], 'fast-answer');
  });

  test('new calls get their own stop token', () async {
    await service.start('first');
    await service.stop();
    await service.start('second');
    await service.stop();
    expect(calls.map((call) => call.arguments['callId']), [
      'first',
      'first',
      'second',
      'second',
    ]);
  });

  test('unsupported platforms are unchanged', () async {
    final disabled = IncomingCallAlertService.forTesting(
      channel: channel,
      supported: false,
    );
    await disabled.start('windows');
    await disabled.stop();
    expect(calls, isEmpty);
  });

  test('native failure does not throw into call handling', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'unavailable'),
        );
    await service.start('failure');
    await service.stop();
  });

  test('empty call identifiers do not ring', () async {
    await service.start('');
    await service.stop();
    expect(calls, isEmpty);
  });
}
