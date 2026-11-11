import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fresh Signal session requires authenticated account', () {
    final source = File('lib/services/socket_service.dart')
        .readAsStringSync();

    final start = source.indexOf(
      'Future<bool> requestFreshE2eeSession(',
    );
    final end = source.indexOf(
      'Future<Map<String, dynamic>> _requestE2eeBundle(',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final method = source.substring(start, end);

    expect(method, contains('!isAuthenticated'));
    expect(method, contains('peer == owner'));
    expect(method, contains('_connectionGeneration'));
    expect(method, contains('identical(channel, _channel)'));
    expect(method, contains('_requestE2eeBundle(peer)'));

    expect(method, isNot(contains('resetPeerSession(')));
    expect(method, isNot(contains('deleteSession(')));
    expect(method, isNot(contains('deleteRemoteIdentity(')));
  });
}