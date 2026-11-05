import 'package:flutter_test/flutter_test.dart';
import '../lib/services/legacy_media_regrant_visibility.dart';

void main() {
  Map<String, dynamic> original() => {
    'isMe': true,
    'from': 'alice',
    'mediaId': 'media_123',
    'messageType': 'image',
  };

  bool visible(
    Map<String, dynamic> message, {
    bool accepted = true,
    String currentUser = 'alice',
    String recipient = 'bob',
  }) {
    return LegacyMediaRegrantVisibility.canOffer(
      message: message,
      currentUser: currentUser,
      recipient: recipient,
      communicationAccepted: accepted,
    );
  }

  test('own eligible image with accepted contact', () {
    expect(visible(original()), isTrue);
  });

  test('recipient must be accepted', () {
    expect(visible(original(), accepted: false), isFalse);
  });

  test('incoming message is excluded', () {
    expect(visible({
      ...original(),
      'isMe': false,
      'from': 'bob',
    }), isFalse);
  });

  test('isMe alone is never proof of sender', () {
    expect(visible({
      ...original(),
      'from': 'someone_else',
    }), isFalse);
  });

  test('forwarded media is excluded', () {
    expect(visible({
      ...original(),
      'forwardedFrom': 'carol',
    }), isFalse);
  });

  test('E2EE media is excluded from legacy regrant', () {
    expect(visible({
      ...original(),
      'e2ee': true,
    }), isFalse);

    expect(visible({
      ...original(),
      'e2eeMedia': {'encrypted': true},
    }), isFalse);
  });

  test('missing and malformed media identifiers are excluded', () {
    expect(visible({
      ...original(),
      'mediaId': '',
    }), isFalse);

    expect(visible({
      ...original(),
      'mediaId': '../../secret',
    }), isFalse);
  });

  test('text messages and unrelated types are excluded', () {
    expect(visible({
      ...original(),
      'messageType': 'text',
    }), isFalse);
  });

  test('different active account is excluded', () {
    expect(
      visible(original(), currentUser: 'other'),
      isFalse,
    );
  });

  test('recipient cannot be the same account', () {
    expect(
      visible(original(), recipient: 'ALICE'),
      isFalse,
    );
  });

  test('video file and voice are eligible types', () {
    for (final type in ['video', 'file', 'voice']) {
      expect(
        visible({
          ...original(),
          'messageType': type,
        }),
        isTrue,
      );
    }
  });
}