import 'package:flutter_test/flutter_test.dart';

import '../lib/services/temporary_e2ee_scope_guard.dart';

void main() {
  final channel = Object();
  bool current({
    int generation = 4,
    Object? activeChannel,
    bool authenticated = true,
    String? owner = 'alice',
    String? accountId = 'account-a',
  }) => TemporaryE2eeScopeGuard.isCurrent(
    eventGeneration: 4,
    currentGeneration: generation,
    eventChannel: channel,
    currentChannel: activeChannel ?? channel,
    isAuthenticated: authenticated,
    expectedOwner: 'alice',
    activeOwner: owner,
    expectedAccountId: 'account-a',
    activeAccountId: accountId,
  );

  test('same account and live socket are accepted', () {
    expect(current(), isTrue);
  });
  test('changed connection generation is rejected', () {
    expect(current(generation: 5), isFalse);
  });
  test('replaced socket is rejected', () {
    expect(current(activeChannel: Object()), isFalse);
  });
  test('logout is rejected', () {
    expect(current(authenticated: false), isFalse);
  });
  test('changed username is rejected', () {
    expect(current(owner: 'bob'), isFalse);
  });
  test('changed account ID is rejected', () {
    expect(current(accountId: 'account-b'), isFalse);
  });
  test('missing account ID is rejected', () {
    expect(current(accountId: null), isFalse);
  });
}
