import 'package:flutter_test/flutter_test.dart';

import '../lib/services/crypto/temporary_signal_e2ee_service.dart';

void main() {
  final sessionId = 'a' * 48;
  final owner = TemporarySignalE2eeService.identityForSession(
    sessionId,
    'owner',
  );
  final guest = TemporarySignalE2eeService.identityForSession(
    sessionId,
    'guest',
  );

  test('different accounts never share temporary Signal key namespace', () {
    final first = TemporarySignalE2eeService.storageIdentityForLocalIdentity(
      'account-1',
      owner,
    );
    final second = TemporarySignalE2eeService.storageIdentityForLocalIdentity(
      'account-2',
      owner,
    );
    expect(first, isNot(second));
    expect(first, endsWith(owner));
    expect(second, endsWith(owner));
  });

  test('owner and guest have separate namespaces', () {
    final first = TemporarySignalE2eeService.storageIdentityForLocalIdentity(
      'account-1',
      owner,
    );
    final second = TemporarySignalE2eeService.storageIdentityForLocalIdentity(
      'account-1',
      guest,
    );
    expect(first, isNot(second));
  });

  test('same account and session keep a stable namespace', () {
    final first = TemporarySignalE2eeService.storageIdentityForLocalIdentity(
      'account-1',
      owner,
    );
    final second = TemporarySignalE2eeService.storageIdentityForLocalIdentity(
      ' account-1 ',
      owner,
    );
    expect(first, second);
  });

  test('missing account scope fails closed', () {
    expect(
      () => TemporarySignalE2eeService(accountId: '  '),
      throwsArgumentError,
    );
    expect(
      () => TemporarySignalE2eeService.storageIdentityForLocalIdentity(
        ' ',
        owner,
      ),
      throwsFormatException,
    );
  });

  test('invalid temporary identity cannot select a storage namespace', () {
    expect(
      () => TemporarySignalE2eeService.storageIdentityForLocalIdentity(
        'account-1',
        'regular-user',
      ),
      throwsFormatException,
    );
  });
}
