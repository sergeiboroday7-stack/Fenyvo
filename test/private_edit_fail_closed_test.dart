import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private edit cannot send plaintext to server', () {
    final source = File('lib/services/socket_service.dart').readAsStringSync();

    final start = source.indexOf('  void editMessage({');
    expect(start, greaterThanOrEqualTo(0));

    final end = source.indexOf(
      '  // ========================================',
      start,
    );
    expect(end, greaterThan(start));

    final method = source.substring(start, end);

    expect(method, contains('plaintext private edit blocked'));
    expect(method, isNot(contains("_send('edit_message'")));
    expect(source, isNot(contains("_send('edit_message'")));
  });
}