import 'package:flutter_test/flutter_test.dart';

import '../lib/services/windows_update_installation_service.dart';

void main() {
  test('queries the supplied app PID, not the PowerShell host PID', () {
    expect(
      windowsAppProcessStartTimeCommand(43210),
      '(Get-Process -Id 43210 -ErrorAction Stop).StartTime.ToUniversalTime().Ticks',
    );
    expect(windowsAppProcessStartTimeCommand(9876), contains('-Id 9876 '));
    expect(windowsAppProcessStartTimeCommand(43210), isNot(contains(r'$pid')));
  });
  test('rejects non-process identifiers before building a command', () {
    for (final id in [0, -1, -9876]) {
      expect(() => windowsAppProcessStartTimeCommand(id), throwsArgumentError);
    }
  });
}
