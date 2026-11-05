import 'package:flutter_test/flutter_test.dart';

import '../lib/services/trust_account_scope.dart';

void main() {
  const prefix = 'spartan_trust_blocked_';

  String? scoped(String owner, String contact) =>
      TrustAccountScope.key(
        owner: owner,
        contact: contact,
        prefix: prefix,
      );

  group('TrustAccountScope', () {
    test('same owner and contact produce a stable key', () {
      expect(scoped('alice', 'bob'), scoped('alice', 'bob'));
    });

    test('different owners cannot share one blocked-contact key', () {
      expect(
        scoped('alice', 'bob'),
        isNot(scoped('charlie', 'bob')),
      );
    });

    test('same owner and different contacts have different keys', () {
      expect(
        scoped('alice', 'bob'),
        isNot(scoped('alice', 'charlie')),
      );
    });

    test('case and surrounding spaces are normalized', () {
      expect(
        scoped(' Alice ', ' BOB '),
        scoped('alice', 'bob'),
      );
    });

    test('owner and contact order stays directional', () {
      expect(
        scoped('alice', 'bob'),
        isNot(scoped('bob', 'alice')),
      );
    });

    test('empty owner is rejected', () {
      expect(scoped(' ', 'bob'), isNull);
    });

    test('empty contact is rejected', () {
      expect(scoped('alice', ''), isNull);
    });

    test('self-contact is rejected', () {
      expect(scoped('alice', 'ALICE'), isNull);
    });

    test('empty prefix is rejected', () {
      expect(
        TrustAccountScope.key(
          owner: 'alice',
          contact: 'bob',
          prefix: '',
        ),
        isNull,
      );
    });

    test('v2 key cannot equal a legacy contact-only key', () {
      expect(
        scoped('alice', 'bob'),
        isNot('${prefix}bob'),
      );
    });

    test('reason key is scoped to the same owner and contact', () {
      final base = scoped('alice', 'bob');
      final reason = TrustAccountScope.reasonKey(
        owner: 'alice',
        contact: 'bob',
        prefix: prefix,
      );

      expect(reason, '${base}_reason');
      expect(
        reason,
        isNot(
          TrustAccountScope.reasonKey(
            owner: 'charlie',
            contact: 'bob',
            prefix: prefix,
          ),
        ),
      );
    });

    test('encoded identities do not cause delimiter collisions', () {
      expect(
        scoped('a_b', 'c'),
        isNot(scoped('a', 'b_c')),
      );
    });

    test('unicode usernames produce deterministic keys', () {
      expect(
        scoped('Олена', 'Іван'),
        scoped('олена', 'іван'),
      );
    });
  });
}