import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal bundle replies are correlated and preview is read-only', () {
    final code = File('lib/services/socket_service.dart').readAsStringSync();
    final handlerStart = code.indexOf("if (type == 'e2ee_prekey_bundle')");
    final handlerEnd = code.indexOf("if (type == 'e2ee_bundle_published')", handlerStart);
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = code.substring(handlerStart, handlerEnd);
    expect(handler, contains("data['requestId']"));
    expect(handler, contains('expectedRequestId'));
    expect(handler, contains('responseRequestId != expectedRequestId'));
    expect(handler.indexOf('responseRequestId != expectedRequestId'),
        lessThan(handler.indexOf('processRemoteBundle(')));
    expect(handler, contains('_e2eePreviewPeers.remove(username)'));
    expect(handler, contains('request.complete(data)'));
    expect(handler.indexOf('_e2eePreviewPeers.remove(username)'),
        lessThan(handler.indexOf('processRemoteBundle(')));

    final requestStart = code.indexOf(' _requestE2eeBundle(String username) async');
    final nextMethod = code.indexOf('Future<void> _sendE2eeMessage(', requestStart);
    expect(requestStart, greaterThanOrEqualTo(0));
    expect(nextMethod, greaterThan(requestStart));
    final request = code.substring(requestStart, nextMethod);
    expect(request, contains("'requestId': requestId"));
    expect(request, contains('_e2eeBundleRequestIds[username]'));
    expect(RegExp(r'_e2eeBundleRequestIds.remove\(username\)')
        .allMatches(request).length, 2);
    expect(request, contains('throw TimeoutException('));
    expect(request, contains('return await completer.future.timeout('));
    expect(code, contains('Future<Map<String, dynamic>> previewE2eeCandidate('));
    expect(code, contains('generation != _connectionGeneration'));
    expect(code, contains('identical(channel, _channel)'));
  });
}
