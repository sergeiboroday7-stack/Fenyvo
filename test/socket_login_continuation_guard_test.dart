import 'package:flutter_test/flutter_test.dart';

import '../lib/services/socket_login_continuation_guard.dart';

void main() {
  bool allowed({
    required int eventGeneration,
    required int currentGeneration,
    required Object? eventChannel,
    required Object? currentChannel,
    bool authenticated = true,
    String expectedOwner = 'alice',
    String? activeOwner = 'alice',
  }) {
    return SocketLoginContinuationGuard.isCurrent(
      eventGeneration: eventGeneration,
      currentGeneration: currentGeneration,
      eventChannel: eventChannel,
      currentChannel: currentChannel,
      isAuthenticated: authenticated,
      expectedOwner: expectedOwner,
      activeOwner: activeOwner,
    );
  }

  test('active authenticated owner and connection accepted', () {
    final channel = Object();
    expect(
      allowed(
        eventGeneration: 5,
        currentGeneration: 5,
        eventChannel: channel,
        currentChannel: channel,
      ),
      isTrue,
    );
  });

  test('account switched during login: rejected', () {
    final channel = Object();
    expect(
      allowed(
        eventGeneration: 5,
        currentGeneration: 5,
        eventChannel: channel,
        currentChannel: channel,
        activeOwner: 'bob',
      ),
      isFalse,
    );
  });

  test('logout during login: rejected', () {
    final channel = Object();
    expect(
      allowed(
        eventGeneration: 5,
        currentGeneration: 6,
        eventChannel: channel,
        currentChannel: null,
        authenticated: false,
        activeOwner: null,
      ),
      isFalse,
    );
  });

  test('authentication revoked without channel change', () {
    final channel = Object();
    expect(
      allowed(
        eventGeneration: 5,
        currentGeneration: 5,
        eventChannel: channel,
        currentChannel: channel,
        authenticated: false,
      ),
      isFalse,
    );
  });

  test('reconnection invalidates pending login continuation', () {
    final oldChannel = Object();
    final newChannel = Object();

    expect(
      allowed(
        eventGeneration: 7,
        currentGeneration: 8,
        eventChannel: oldChannel,
        currentChannel: newChannel,
      ),
      isFalse,
    );

    expect(
      allowed(
        eventGeneration: 8,
        currentGeneration: 8,
        eventChannel: newChannel,
        currentChannel: newChannel,
      ),
      isTrue,
    );
  });

  test('same generation but different socket is rejected', () {
    expect(
      allowed(
        eventGeneration: 9,
        currentGeneration: 9,
        eventChannel: Object(),
        currentChannel: Object(),
      ),
      isFalse,
    );
  });

  test('empty owner and missing active owner are rejected', () {
    final channel = Object();

    expect(
      allowed(
        eventGeneration: 1,
        currentGeneration: 1,
        eventChannel: channel,
        currentChannel: channel,
        expectedOwner: '',
      ),
      isFalse,
    );

    expect(
      allowed(
        eventGeneration: 1,
        currentGeneration: 1,
        eventChannel: channel,
        currentChannel: channel,
        activeOwner: null,
      ),
      isFalse,
    );
  });

  test('account names use the existing exact comparison', () {
    final channel = Object();

    expect(
      allowed(
        eventGeneration: 1,
        currentGeneration: 1,
        eventChannel: channel,
        currentChannel: channel,
        activeOwner: 'Alice',
      ),
      isFalse,
    );
  });
}
