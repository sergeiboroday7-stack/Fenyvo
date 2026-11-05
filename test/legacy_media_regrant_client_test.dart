import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/legacy_media_regrant_client.dart';

void main() {
  late ValueNotifier<bool> connected;
  late void Function(Map<String, dynamic>)? listener;
  late LegacyMediaRegrantClient client;
  var sent = 0;
  var lastId = '';

  setUp(() {
    connected = ValueNotifier<bool>(true);
    listener = null;
    sent = 0;
    lastId = '';

    client = LegacyMediaRegrantClient.test(
      send: ({
        required mediaId,
        required recipient,
        required ownerConfirmed,
        required requestId,
      }) {
        sent++;
        lastId = requestId;
        return true;
      },
      subscribe: (handler) => listener = handler,
      unsubscribe: (handler) => listener = null,
      isConnected: () => connected.value,
      connectionChanges: connected,
      timeout: const Duration(milliseconds: 100),
    );
  });

  tearDown(() {
    client.dispose();
    connected.dispose();
  });

  Future<void> flush() =>
      Future<void>.delayed(const Duration(milliseconds: 1));

  test('successful matching server response is accepted', () async {
    final future = client.request(
      mediaId: 'media1',
      recipient: 'bob',
      ownerConfirmed: true,
    );

    await flush();
    expect(sent, 1);
    expect(lastId, isNotEmpty);

    listener?.call({
      'type': 'legacy_media_regrant_result',
      'requestId': lastId,
      'ok': true,
    });

    expect((await future).approved, isTrue);
  });

  test('stale server response cannot complete current request', () async {
    final future = client.request(
      mediaId: 'media1',
      recipient: 'bob',
      ownerConfirmed: true,
    );

    listener?.call({
      'type': 'legacy_media_regrant_result',
      'requestId': 'outdated',
      'ok': true,
    });

    expect(client.isPending, isTrue);

    listener?.call({
      'type': 'legacy_media_regrant_result',
      'requestId': lastId,
      'ok': false,
      'reason': 'RECIPIENT_NOT_ELIGIBLE',
    });

    expect((await future).approved, isFalse);
  });

  test('disconnect cancels waiting request', () async {
    final future = client.request(
      mediaId: 'media1',
      recipient: 'bob',
      ownerConfirmed: true,
    );

    connected.value = false;
    expect((await future).reason, 'DISCONNECTED');
    expect(client.isPending, isFalse);
  });

  test('timeout releases pending request', () async {
    final future = client.request(
      mediaId: 'media1',
      recipient: 'bob',
      ownerConfirmed: true,
    );

    expect((await future).reason, 'TIMEOUT');
    expect(client.isPending, isFalse);
  });

  test('double submission is rejected', () async {
    final first = client.request(
      mediaId: 'media1',
      recipient: 'bob',
      ownerConfirmed: true,
    );

    final second = await client.request(
      mediaId: 'media2',
      recipient: 'bob',
      ownerConfirmed: true,
    );

    expect(second.approved, isFalse);
    expect(sent, 1);

    listener?.call({
      'type': 'legacy_media_regrant_result',
      'requestId': lastId,
      'ok': true,
    });

    expect((await first).approved, isTrue);
  });

  test('no submission without explicit confirmation', () async {
    final result = await client.request(
      mediaId: 'media1',
      recipient: 'bob',
      ownerConfirmed: false,
    );

    expect(result.approved, isFalse);
    expect(sent, 0);
  });
}