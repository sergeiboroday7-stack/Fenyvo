import 'package:flutter_test/flutter_test.dart';
import '../lib/services/temporary_chat_history_store.dart';

void main() {
  final id = 'a' * 48;
  final now = DateTime.now().toUtc();
  final expiry = now.add(const Duration(days: 1));
  test('history is scoped separately by account session and role', () {
    expect(TemporaryHistoryCodec.keyFor('a', id, 'owner'),
        isNot(TemporaryHistoryCodec.keyFor('b', id, 'owner')));
    expect(TemporaryHistoryCodec.keyFor('a', id, 'owner'),
        isNot(TemporaryHistoryCodec.keyFor('a', id, 'guest')));
  });
  test('invalid identity or role fails closed', () {
    expect(() => TemporaryHistoryCodec.keyFor('a', 'invalid', 'owner'),
        throwsFormatException);
    expect(() => TemporaryHistoryCodec.keyFor('a', id, 'other'),
        throwsFormatException);
  });
  test('valid history survives codec roundtrip', () {
    final input = [TemporaryHistoryLine(
        text: 'encrypted-at-rest only', outgoing: true, timestamp: now)];
    final serialized = TemporaryHistoryCodec.encode(input, expiry);
    final result = TemporaryHistoryCodec.decode(serialized, now);
    expect(result.length, 1);
    expect(result.single.text, input.single.text);
    expect(result.single.outgoing, true);
  });
  test('expired history is hidden', () {
    final serialized = TemporaryHistoryCodec.encode([
      TemporaryHistoryLine(text: 'text', outgoing: false, timestamp: now),
    ], expiry);
    expect(TemporaryHistoryCodec.decode(
        serialized, expiry.add(const Duration(seconds: 1))), isEmpty);
  });
  test('malformed and oversized records fail closed', () {
    expect(TemporaryHistoryCodec.decode('{', now), isEmpty);
    expect(TemporaryHistoryCodec.decode('x' * 40001, now), isEmpty);
  });
  test('record count is bounded', () {
    final list = List.generate(100, (i) => TemporaryHistoryLine(
      text: 'line $i', outgoing: i.isEven, timestamp: now,
    ));
    final result = TemporaryHistoryCodec.decode(
        TemporaryHistoryCodec.encode(list, expiry), now);
    expect(result.length, TemporaryHistoryCodec.maxLines);
    expect(result.first.text, 'line 40');
  });
}
