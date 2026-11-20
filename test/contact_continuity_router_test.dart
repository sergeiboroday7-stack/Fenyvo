import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/crypto/contact_continuity_router.dart';

void main() {
  Map<String, dynamic> directory() => {
    'username': 'Bob',
    'accountId': 'account',
    'available': true,
    'fromEpoch': 0,
    'toEpoch': 1,
    'currentEpoch': 1,
    'certificates': [
      {'payload': {}, 'signature': 'synthetic-public-test'},
    ],
  };
  test(
    'unchanged or unpinned peer does not fetch or apply continuity',
    () async {
      for (final key in [null, 'new']) {
        var fetched = false, applied = false;
        final router = ContactContinuityRouter(
          readHead: (_) async => {
            'identityKey': key,
            'epoch': 0,
            'accountId': null,
          },
          fetchDirectory: (_, __) async {
            fetched = true;
            return directory();
          },
          applyVerified: (_, __, ___, ____, _____) async {
            applied = true;
          },
        );
        expect(
          await router.applyIfChanged('Bob', {
            'identityKey': 'new',
          }, isCurrent: () => true),
          isFalse,
        );
        expect(fetched, isFalse);
        expect(applied, isFalse);
      }
    },
  );
  test('changed pinned key passes bound full chain to verified transactional apply', () async {
    var applied = false;
    final router = ContactContinuityRouter(
      readHead: (_) async => {
        'identityKey': 'old',
        'epoch': 0,
        'accountId': 'account',
      },
      fetchDirectory: (peer, epoch) async {
        expect(peer, 'Bob');
        expect(epoch, 0);
        return directory();
      },
      applyVerified: (peer, bundle, account, certificates, current) async {
        expect(peer, 'Bob');
        expect(bundle['identityKey'], 'new');
        expect(account, 'account');
        expect(certificates.length, 1);
        expect(current(), isTrue);
        applied = true;
      },
    );
    expect(
      await router.applyIfChanged('Bob', {
        'identityKey': 'new',
      }, isCurrent: () => true),
      isTrue,
    );
    expect(applied, isTrue);
  });
  for (final change in <String, dynamic>{
    'username': 'Eve',
    'accountId': 'other',
    'available': false,
    'fromEpoch': 1,
    'toEpoch': 2,
    'currentEpoch': 2,
    'certificates': [],
  }.entries) {
    test(
      'mismatched directory ' + change.key + ' cannot reach trust apply',
      () async {
        var applied = false;
        final router = ContactContinuityRouter(
          readHead: (_) async => {
            'identityKey': 'old',
            'epoch': 0,
            'accountId': 'account',
          },
          fetchDirectory: (_, __) async =>
              directory()..[change.key] = change.value,
          applyVerified: (_, __, ___, ____, _____) async {
            applied = true;
          },
        );
        await expectLater(
          router.applyIfChanged('Bob', {
            'identityKey': 'new',
          }, isCurrent: () => true),
          throwsStateError,
        );
        expect(applied, isFalse);
      },
    );
  }
  test('session change during network await cannot apply trust', () async {
    var current = true, applied = false;
    final router = ContactContinuityRouter(
      readHead: (_) async => {'identityKey': 'old', 'epoch': 0},
      fetchDirectory: (_, __) async {
        current = false;
        return directory();
      },
      applyVerified: (_, __, ___, ____, _____) async {
        applied = true;
      },
    );
    await expectLater(
      router.applyIfChanged('Bob', {
        'identityKey': 'new',
      }, isCurrent: () => current),
      throwsStateError,
    );
    expect(applied, isFalse);
  });
  test(
    'native verified apply failure propagates without success claim',
    () async {
      final router = ContactContinuityRouter(
        readHead: (_) async => {'identityKey': 'old', 'epoch': 0},
        fetchDirectory: (_, __) async => directory(),
        applyVerified: (_, __, ___, ____, _____) async {
          throw StateError('Native signature invalid');
        },
      );
      await expectLater(
        router.applyIfChanged('Bob', {
          'identityKey': 'new',
        }, isCurrent: () => true),
        throwsStateError,
      );
    },
  );
}
