import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incoming prekey bundle checks socket generation before mutation', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final start = source.indexOf(
      "if (type == 'e2ee_prekey_bundle')",
    );
    final end = source.indexOf(
      "if (type == 'e2ee_bundle_published')",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);

    final generationCheck =
        handler.indexOf('SocketEventGenerationGuard.isCurrent(');
    final requestRemoval =
        handler.indexOf('_e2eeBundleRequests.remove(username)');
    final sessionMutation =
        handler.indexOf('processRemoteBundle(');

    expect(generationCheck, greaterThanOrEqualTo(0));
    expect(requestRemoval, greaterThan(generationCheck));
    expect(sessionMutation, greaterThan(requestRemoval));
    expect(handler, contains('!isAuthenticated'));
    expect(handler, contains('currentUser?.trim()'));
  });
}