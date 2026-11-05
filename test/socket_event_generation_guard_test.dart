import 'package:flutter_test/flutter_test.dart';

import '../lib/services/socket_event_generation_guard.dart';

void main() {
  bool current(
    int eventGeneration,
    int activeGeneration,
    Object? eventChannel,
    Object? activeChannel,
  ) {
    return SocketEventGenerationGuard.isCurrent(
      eventGeneration: eventGeneration,
      currentGeneration: activeGeneration,
      eventChannel: eventChannel,
      currentChannel: activeChannel,
    );
  }

  test('active generation and same channel accepted', () {
    final channel = Object();

    expect(current(2, 2, channel, channel), isTrue);
  });

  test('old generation rejected', () {
    final oldChannel = Object();

    expect(current(1, 2, oldChannel, oldChannel), isFalse);
  });

  test('different channel rejected even with same generation', () {
    expect(current(3, 3, Object(), Object()), isFalse);
  });

  test('null current channel rejected', () {
    expect(current(4, 4, Object(), null), isFalse);
  });

  test('null event channel rejected', () {
    expect(current(4, 4, null, Object()), isFalse);
  });

  test('replaced channel cannot dispatch after reconnect', () {
    final oldChannel = Object();
    final replacement = Object();

    expect(current(7, 7, oldChannel, oldChannel), isTrue);
    expect(current(7, 8, oldChannel, replacement), isFalse);
    expect(current(8, 8, replacement, replacement), isTrue);
  });

  test('identity is used, not value equality', () {
    final first = <int>[1];
    final second = <int>[1];

    expect(first == second, isFalse);
    expect(current(9, 9, first, second), isFalse);
  });
}