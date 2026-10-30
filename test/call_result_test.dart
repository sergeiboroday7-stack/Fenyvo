import 'package:fenyvo/services/app_language_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/call_result.dart';
import 'package:fenyvo/services/call_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppLanguageService.instance.code.value = 'ru';
  test('caller cancelling an unanswered incoming call means missed', () {
    expect(
      CallResult.remoteEnd(incoming: true, connected: false, accepted: false),
      CallOutcome.missed,
    );
    expect(
      CallHistoryService.status({'outcome': 'missed'}),
      'Пропущенный звонок',
    );
  });
  test('answered calls and outgoing failures are not called missed', () {
    expect(
      CallResult.remoteEnd(incoming: true, connected: true, accepted: true),
      CallOutcome.completed,
    );
    expect(
      CallResult.remoteEnd(incoming: true, connected: false, accepted: true),
      CallOutcome.failed,
    );
    expect(
      CallResult.remoteEnd(incoming: false, connected: false, accepted: false),
      CallOutcome.failed,
    );
  });
  test('history keeps actual failure and completed duration', () {
    expect(
      CallHistoryService.status({
        'outcome': 'failed',
        'reason': 'Пользователь не в сети',
      }),
      'Пользователь не в сети',
    );
    expect(CallHistoryService.status({'outcome': 'declined'}), 'Отклонён');
    expect(CallHistoryService.status({'outcome': 'cancelled'}), 'Отменён');
    expect(
      CallHistoryService.status({'connected': true, 'seconds': 65}),
      '01:05',
    );
    expect(CallHistoryService.status({}), 'Без соединения');
    expect(
      CallHistoryService.title({'incoming': false, 'video': false}),
      'Исходящий аудиозвонок',
    );
    expect(
      CallHistoryService.title({'incoming': true, 'video': true}),
      'Входящий видеозвонок',
    );
  });
}
