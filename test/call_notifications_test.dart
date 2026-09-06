import 'package:flutter_test/flutter_test.dart';
import 'package:spartan_chat_final/services/app_visibility.dart';
import 'package:spartan_chat_final/services/call_clock.dart';
import 'package:spartan_chat_final/services/system_call_service.dart';

void main() {
  test('selected chat only suppresses alerts while visible', () {
    expect(AppVisibility.shouldNotify(foreground: true, sameChat: true), false);
    expect(AppVisibility.shouldNotify(foreground: false, sameChat: true), true);
    expect(AppVisibility.shouldNotify(foreground: true, sameChat: false), true);
  });
  test('duration excludes ringing and supports hours', () {
    final clock = CallClock();
    expect(clock.connected, false);
    expect(clock.label, '00:00');
    clock.connect();
    expect(clock.connected, true);
    clock.connect();
    clock.stop();
    clock.reset();
    expect(clock.connected, false);
    expect(CallClock.format(const Duration(seconds: 65)), '01:05');
    expect(
      CallClock.format(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '01:02:03',
    );
  });
  test('stale or malformed incoming pushes cannot ring', () {
    final data = <String, dynamic>{
      'callId': 'call',
      'sender': 'Alice',
      'expiresAt': 75000,
    };
    expect(SystemCallService.validInvite(data, 1000), true);
    expect(SystemCallService.validInvite(data, 75000), false);
    expect(
      SystemCallService.validInvite({...data, 'expiresAt': 999999}, 1000),
      false,
    );
    expect(SystemCallService.validInvite({...data, 'callId': ''}, 1000), false);
  });
}
