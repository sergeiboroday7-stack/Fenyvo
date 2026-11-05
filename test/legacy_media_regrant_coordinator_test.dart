import 'package:flutter_test/flutter_test.dart';
import '../lib/services/legacy_media_regrant_coordinator.dart';

void main() {
  var sends = 0;
  late LegacyMediaRegrantCoordinator coordinator;

  setUp(() {
    sends = 0;
    coordinator = LegacyMediaRegrantCoordinator(
      send: ({
        required String mediaId,
        required String recipient,
        required bool ownerConfirmed,
        required String requestId,
      }) {
        sends++;
        return true;
      },
    );
  });

  bool submit(String id, {bool confirmed = true}) {
    return coordinator.request(
      mediaId: 'media_160',
      recipient: 'bob',
      ownerConfirmed: confirmed,
      requestId: id,
    );
  }

  test('owner confirmation is required', () {
    expect(submit('request_a', confirmed: false), isFalse);
    expect(sends, 0);
    expect(coordinator.isPending, isFalse);
  });

  test('duplicate request is blocked while pending', () {
    expect(submit('request_a'), isTrue);
    expect(submit('request_b'), isFalse);
    expect(sends, 1);
    expect(coordinator.isPending, isTrue);
  });

  test('unrelated message does not complete pending request', () {
    expect(submit('request_a'), isTrue);
    expect(
      coordinator.acceptServerMessage({
        'type': 'message_sent',
        'requestId': 'request_a',
        'ok': true,
      }),
      isNull,
    );
    expect(coordinator.isPending, isTrue);
  });

  test('matching server approval completes request', () {
    expect(submit('request_a'), isTrue);
    final result = coordinator.acceptServerMessage({
      'type': 'legacy_media_regrant_result',
      'requestId': 'request_a',
      'ok': true,
    });
    expect(result?.approved, isTrue);
    expect(coordinator.isPending, isFalse);
  });

  test('server denial never becomes success', () {
    expect(submit('request_b'), isTrue);
    final result = coordinator.acceptServerMessage({
      'type': 'legacy_media_regrant_result',
      'requestId': 'request_b',
      'ok': false,
      'reason': 'RECIPIENT_NOT_ELIGIBLE',
    });
    expect(result?.approved, isFalse);
    expect(coordinator.isPending, isFalse);
  });

  test('old or missing request ID cannot complete a request', () {
    expect(submit('new_request'), isTrue);

    expect(
      coordinator.acceptServerMessage({
        'type': 'legacy_media_regrant_result',
        'requestId': 'old_request',
        'ok': true,
      }),
      isNull,
    );

    expect(
      coordinator.acceptServerMessage({
        'type': 'legacy_media_regrant_result',
        'ok': true,
      }),
      isNull,
    );

    expect(coordinator.isPending, isTrue);
  });

  test('invalid request ID is rejected before sending', () {
    expect(submit('bad request id'), isFalse);
    expect(sends, 0);
  });

  test('reset clears pending request', () {
    expect(submit('request_a'), isTrue);
    coordinator.reset();
    expect(coordinator.isPending, isFalse);
  });

  test('failed transport leaves no pending request', () {
    final failed = LegacyMediaRegrantCoordinator(
      send: ({
        required String mediaId,
        required String recipient,
        required bool ownerConfirmed,
        required String requestId,
      }) => false,
    );

    expect(
      failed.request(
        mediaId: 'media_160',
        recipient: 'bob',
        ownerConfirmed: true,
        requestId: 'failed_request',
      ),
      isFalse,
    );
    expect(failed.isPending, isFalse);
  });
}