import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_attachment_helpers.dart';

void main() {
  group('PrivateAttachmentHelpers', () {
    test('message type defaults to text', () {
      expect(PrivateAttachmentHelpers.messageType({}), 'text');
      expect(
        PrivateAttachmentHelpers.messageType({'messageType': ' VIDEO '}),
        'video',
      );
      expect(PrivateAttachmentHelpers.messageType({'messageType': ''}), 'text');
    });

    test('basename handles Windows and Unix paths', () {
      expect(
        PrivateAttachmentHelpers.basename(r'C:\files\photo.jpg'),
        'photo.jpg',
      );
      expect(PrivateAttachmentHelpers.basename('/tmp/voice.mp3'), 'voice.mp3');
      expect(PrivateAttachmentHelpers.basename('file.pdf'), 'file.pdf');
    });

    test('filename removes forbidden characters', () {
      expect(PrivateAttachmentHelpers.safeFileName('a:b?.jpg'), 'a_b_.jpg');
      expect(PrivateAttachmentHelpers.safeFileName(' hello.txt '), 'hello.txt');

      final fallback = PrivateAttachmentHelpers.safeFileName(' ');
      expect(fallback, startsWith('spartan_'));
      expect(fallback, endsWith('.bin'));
    });

    test('MIME recognizes supported formats', () {
      expect(
        PrivateAttachmentHelpers.mimeFromName('photo.JPG', 'fallback'),
        'image/jpeg',
      );
      expect(
        PrivateAttachmentHelpers.mimeFromName('movie.mp4', 'fallback'),
        'video/mp4',
      );
      expect(
        PrivateAttachmentHelpers.mimeFromName('report.pdf', 'fallback'),
        'application/pdf',
      );
      expect(
        PrivateAttachmentHelpers.mimeFromName('unknown.xyz', 'fallback'),
        'fallback',
      );
    });
  });
}
