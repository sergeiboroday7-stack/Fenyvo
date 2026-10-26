import 'package:fenyvo/services/message_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds text without case sensitivity', () {
    expect(
      MessageSearchService.matches({
        'text': 'Встречаемся у метро в 18:30',
      }, 'МЕТРО'),
      isTrue,
    );
  });

  test('finds file names, forward comments and replied text', () {
    expect(
      MessageSearchService.matches({'fileName': 'Договор.pdf'}, 'договор'),
      isTrue,
    );
    expect(
      MessageSearchService.matches({
        'forwardComment': 'Посмотри вечером',
      }, 'вечером'),
      isTrue,
    );
    expect(
      MessageSearchService.matches({
        'replyTo': {'from': 'Alla', 'text': 'Секретная фраза'},
      }, 'фраза'),
      isTrue,
    );
  });

  test('empty query and unrelated content do not match', () {
    expect(MessageSearchService.matches({'text': 'Привет'}, '  '), isFalse);
    expect(
      MessageSearchService.matches({'text': 'Привет'}, 'встреча'),
      isFalse,
    );
  });
}
