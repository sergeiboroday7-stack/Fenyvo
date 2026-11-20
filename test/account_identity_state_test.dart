import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/account_identity_state.dart';

void main() {
  const one = '11111111-1111-4111-8111-111111111111';
  const two = '22222222-2222-4222-8222-222222222222';
  test('valid ID is available only to its owner', () {
    final s = AccountIdentityState()..bind(username: 'Alice', accountId: one);
    expect(s.accountIdFor('Alice'), one);
    expect(s.accountIdFor('Bob'), isNull);
    expect(s.accountIdFor(null), isNull);
  });
  test('old server without ID remains compatible', () {
    final s = AccountIdentityState()..bind(username: 'Alice');
    expect(s.accountIdFor('Alice'), isNull);
  });
  test('account switch clears previous ID', () {
    final s = AccountIdentityState()..bind(username: 'Alice', accountId: one);
    s.bind(username: 'Bob');
    expect(s.accountIdFor('Alice'), isNull);
    expect(s.accountIdFor('Bob'), isNull);
    s.bind(username: 'Bob', accountId: two);
    expect(s.accountIdFor('Bob'), two);
  });
  test('malformed values clear previous ID', () {
    for (final value in <Object?>[
      null,
      '',
      'invalid',
      42,
      <String>[],
      'ABCDEFAB-1111-4111-8111-111111111111',
    ]) {
      final s = AccountIdentityState()..bind(username: 'Alice', accountId: one);
      s.bind(username: 'Alice', accountId: value);
      expect(s.accountIdFor('Alice'), isNull);
    }
  });
  test('logout clears ID', () {
    final s = AccountIdentityState()..bind(username: 'Alice', accountId: one);
    s.clear();
    expect(s.accountIdFor('Alice'), isNull);
  });
  test('empty owner cannot bind ID', () {
    final s = AccountIdentityState()..bind(username: ' ', accountId: one);
    expect(s.accountIdFor(' '), isNull);
  });
  test('case aliases are not guessed', () {
    final s = AccountIdentityState()..bind(username: 'Alice', accountId: one);
    expect(s.accountIdFor('alice'), isNull);
  });
  final source = File('lib/services/socket_service.dart').readAsStringSync();
  test('ID binds after stale login guard', () {
    final bind = source.indexOf('_accountIdentity.bind(');
    final guard = source.lastIndexOf('if (!loginStillCurrent()) return;', bind);
    final presence = source.indexOf('_syncPresence();', bind);
    expect(guard, greaterThanOrEqualTo(0));
    expect(bind, greaterThan(guard));
    expect(presence, greaterThan(bind));
  });
  test('getter requires authentication', () {
    expect(
      source,
      contains(
        'isAuthenticated ? _accountIdentity.accountIdFor(currentUser) : null',
      ),
    );
  });
  test('logout clears ID before async cleanup', () {
    final start = source.indexOf('Future<void> disconnect(');
    final clear = source.indexOf('_accountIdentity.clear();', start);
    final cleanup = source.indexOf(
      'await SystemCallService.clearAccount()',
      start,
    );
    expect(clear, greaterThan(start));
    expect(cleanup, greaterThan(clear));
  });
}
