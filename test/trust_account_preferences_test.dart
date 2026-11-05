import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/fenyvo_trust_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('blocking one account does not block another', () async {
    await FenyvoTrustService.setBlocked('bob', true, owner: 'alice');

    expect(await FenyvoTrustService.isBlocked('bob', owner: 'alice'), isTrue);
    expect(
      await FenyvoTrustService.isBlocked('bob', owner: 'charlie'),
      isFalse,
    );
  });

  test('unblock affects only the selected owner', () async {
    await FenyvoTrustService.setBlocked('bob', true, owner: 'alice');
    await FenyvoTrustService.setBlocked('bob', true, owner: 'charlie');
    await FenyvoTrustService.setBlocked('bob', false, owner: 'alice');

    expect(await FenyvoTrustService.isBlocked('bob', owner: 'alice'), isFalse);
    expect(await FenyvoTrustService.isBlocked('bob', owner: 'charlie'), isTrue);
  });

  test('legacy global blocked preference is not inherited', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('spartan_trust_blocked_bob', true);

    expect(await FenyvoTrustService.isBlocked('bob', owner: 'alice'), isFalse);
    expect(prefs.getBool('spartan_trust_blocked_bob'), isTrue);
  });

  test('remote trust state is account isolated', () async {
    await FenyvoTrustService.applyRemote(
      'bob',
      trusted: true,
      blocked: true,
      reported: true,
      reportReason: 'spam',
      owner: 'alice',
    );

    expect(await FenyvoTrustService.isTrusted('bob', owner: 'alice'), isTrue);
    expect(await FenyvoTrustService.isBlocked('bob', owner: 'alice'), isTrue);
    expect(await FenyvoTrustService.isReported('bob', owner: 'alice'), isTrue);
    expect(
      await FenyvoTrustService.reportReason('bob', owner: 'alice'),
      'spam',
    );

    expect(
      await FenyvoTrustService.isBlocked('bob', owner: 'charlie'),
      isFalse,
    );
    expect(
      await FenyvoTrustService.isReported('bob', owner: 'charlie'),
      isFalse,
    );
  });

  test('missing or self owner cannot persist trust decisions', () async {
    await FenyvoTrustService.setBlocked('bob', true, owner: '');
    await FenyvoTrustService.setBlocked('bob', true, owner: 'bob');

    expect(await FenyvoTrustService.isBlocked('bob', owner: 'alice'), isFalse);
  });

  test('unrelated account report reasons remain independent', () async {
    await FenyvoTrustService.report('bob', reason: 'spam', owner: 'alice');
    await FenyvoTrustService.report('bob', reason: 'other', owner: 'charlie');

    expect(
      await FenyvoTrustService.reportReason('bob', owner: 'alice'),
      'spam',
    );
    expect(
      await FenyvoTrustService.reportReason('bob', owner: 'charlie'),
      'other',
    );
  });
}
