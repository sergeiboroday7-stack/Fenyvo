import '../lib/services/message_search_service.dart';

void expectMatch(Map<String, dynamic> message, String query, bool expected) {
  final actual = MessageSearchService.matches(message, query);
  if (actual != expected) {
    throw StateError(
      'Search mismatch for query "$query": expected $expected, got $actual',
    );
  }
}

void main() {
  expectMatch({'text': 'Встречаемся у метро в 18:30'}, 'МЕТРО', true);
  expectMatch({'fileName': 'Договор.pdf'}, 'договор', true);
  expectMatch({'forwardComment': 'Посмотри вечером'}, 'вечером', true);
  expectMatch(
    {
      'replyTo': {'from': 'Alla', 'text': 'Секретная фраза'},
    },
    'фраза',
    true,
  );
  expectMatch({'text': 'Привет'}, '  ', false);
  expectMatch({'text': 'Привет'}, 'встреча', false);
}
