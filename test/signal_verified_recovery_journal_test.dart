import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending recovery is restored before Signal key maintenance', () {
    final service = File('lib/services/crypto/signal_e2ee_service.dart')
        .readAsStringSync();
    final initialization = service.substring(
      service.indexOf('Future<void> _initializeForUserInternal('),
      service.indexOf('Lock _lockFor('),
    );
    expect(initialization, contains('restorePendingVerifiedPeerRecovery()'));
    expect(
      initialization.indexOf('restorePendingVerifiedPeerRecovery()'),
      lessThan(initialization.indexOf('_ensurePreKeys()')),
    );
  });

  test('recovery journal is written before trusted state is modified', () {
    final service = File('lib/services/crypto/signal_e2ee_service.dart')
        .readAsStringSync();
    final recovery = service.substring(
      service.indexOf('Future<void> acceptVerifiedRemoteBundle('),
      service.indexOf('Future<Map<String, dynamic>> encrypt('),
    );
    expect(recovery, contains('_verifiedRecoveryLock.synchronized('));
    expect(recovery, contains('beginVerifiedPeerRecovery('));
    expect(recovery, contains('restorePendingVerifiedPeerRecovery()'));
    expect(recovery, contains('commitVerifiedPeerRecovery()'));
    expect(
      recovery.indexOf('beginVerifiedPeerRecovery('),
      lessThan(recovery.indexOf('await store.deleteSession(address);')),
    );
    expect(
      recovery.indexOf('processPreKeyBundle(address, bundle)'),
      lessThan(recovery.indexOf('commitVerifiedPeerRecovery()')),
    );
  });

  test('journal is account scoped and cleared only after restore', () {
    final store = File('lib/services/crypto/signal_secure_store.dart')
        .readAsStringSync();
    expect(store, contains("_key('verified_recovery', 'pending')"));
    expect(store, contains('final String localUsername;'));
    final restoration = store.substring(
      store.indexOf('Future<void> restorePendingVerifiedPeerRecovery()'),
      store.indexOf('Future<void> commitVerifiedPeerRecovery()'),
    );
    expect(restoration, contains('await deleteSession(address)'));
    expect(restoration, contains('await deleteRemoteIdentity(address)'));
    expect(restoration, contains('await storeSession(address, oldSession)'));
    expect(
      restoration.indexOf('await storeSession(address, oldSession)'),
      lessThan(restoration.indexOf("await _storage.delete(key: _key('verified_recovery', 'pending'))")),
    );
  });
}
