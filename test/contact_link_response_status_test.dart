import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/contact_link_screen.dart';

void main() {
  test('acceptance updates the request sender', () {
    expect(
      contactLinkResponseStatus(
        username: 'Bob',
        currentUser: 'Alice',
        data: {'from': 'Alice', 'to': 'Bob', 'status': 'accepted'},
      ),
      'accepted',
    );
  });

  test('decline updates the request sender', () {
    expect(
      contactLinkResponseStatus(
        username: 'bob',
        currentUser: 'alice',
        data: {'from': 'alice', 'to': 'bob', 'status': 'declined'},
      ),
      'declined',
    );
  });

  test('acceptance updates the recipient viewing the sender', () {
    expect(
      contactLinkResponseStatus(
        username: 'Alice',
        currentUser: 'Bob',
        data: {'from': 'Alice', 'to': 'Bob', 'status': 'accepted'},
      ),
      'accepted',
    );
  });

  test('unrelated contact event is ignored', () {
    expect(
      contactLinkResponseStatus(
        username: 'charlie',
        currentUser: 'alice',
        data: {'from': 'alice', 'to': 'bob', 'status': 'accepted'},
      ),
      isNull,
    );
  });

  test('other account event is ignored', () {
    expect(
      contactLinkResponseStatus(
        username: 'bob',
        currentUser: 'charlie',
        data: {'from': 'alice', 'to': 'bob', 'status': 'accepted'},
      ),
      isNull,
    );
  });

  test('unknown status and malformed event are ignored', () {
    expect(
      contactLinkResponseStatus(
        username: 'bob',
        currentUser: 'alice',
        data: {'from': 'alice', 'to': 'bob', 'status': 'pending'},
      ),
      isNull,
    );
    expect(
      contactLinkResponseStatus(
        username: 'bob',
        currentUser: 'alice',
        data: {'from': 'alice', 'status': 'accepted'},
      ),
      isNull,
    );
  });

  test('self-contact and empty owner are ignored', () {
    expect(
      contactLinkResponseStatus(
        username: 'alice',
        currentUser: 'alice',
        data: {'from': 'alice', 'to': 'alice', 'status': 'accepted'},
      ),
      isNull,
    );
    expect(
      contactLinkResponseStatus(
        username: 'bob',
        currentUser: '',
        data: {'from': 'alice', 'to': 'bob', 'status': 'accepted'},
      ),
      isNull,
    );
  });
}
