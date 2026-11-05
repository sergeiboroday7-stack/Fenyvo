import 'package:flutter_test/flutter_test.dart';
import '../lib/services/message_content_gate.dart';

void main() {
  group('hasMessageContent', () {
    test('accepts ordinary text', () {
      expect(hasMessageContent({'text': 'hello'}), isTrue);
    });

    test('rejects whitespace-only text', () {
      expect(hasMessageContent({'text': '  \n  '}), isFalse);
    });

    test('accepts image media ID without caption', () {
      expect(
        hasMessageContent({
          'text': '',
          'messageType': 'image',
          'mediaId': 'media-001',
        }),
        isTrue,
      );
    });

    test('accepts video data without caption', () {
      expect(
        hasMessageContent({
          'text': '',
          'messageType': 'video',
          'mediaData': 'payload',
        }),
        isTrue,
      );
    });

    test('accepts voice data without text', () {
      expect(
        hasMessageContent({
          'text': '',
          'messageType': 'voice',
          'voiceData': 'audio-payload',
        }),
        isTrue,
      );
    });

    test('accepts encrypted media metadata with payload reference', () {
      expect(
        hasMessageContent({
          'text': '',
          'e2eeMedia': {'encryptedRef': 'opaque-reference'},
        }),
        isTrue,
      );
    });

    test('rejects an empty encrypted media map', () {
      expect(
        hasMessageContent({'text': '', 'e2eeMedia': {}}),
        isFalse,
      );
    });

    test('rejects empty values in encrypted media map', () {
      expect(
        hasMessageContent({
          'text': '',
          'e2eeMedia': {'encryptedRef': '  '},
        }),
        isFalse,
      );
    });

    test('rejects media type alone', () {
      expect(
        hasMessageContent({
          'text': '',
          'messageType': 'image',
        }),
        isFalse,
      );
    });

    test('rejects file name and MIME type alone', () {
      expect(
        hasMessageContent({
          'text': '',
          'messageType': 'file',
          'fileName': 'document.pdf',
          'mimeType': 'application/pdf',
        }),
        isFalse,
      );
    });

    test('rejects empty media fields', () {
      expect(
        hasMessageContent({
          'text': '',
          'mediaId': ' ',
          'mediaData': '',
          'voiceData': '',
        }),
        isFalse,
      );
    });

    test('rejects a completely empty event', () {
      expect(hasMessageContent({}), isFalse);
    });

    test('does not require an ID for structural content check', () {
      expect(
        hasMessageContent({
          'text': '',
          'mediaId': 'legacy-media',
        }),
        isTrue,
      );
    });
  });
}