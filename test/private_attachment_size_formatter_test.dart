import 'package:flutter_test/flutter_test.dart';
import '../lib/features/messages/domain/private_attachment_size_formatter.dart';

void main() {
  String en(String key) => {
        'chatSizeBytes': 'B',
        'chatSizeKilobytes': 'KB',
        'chatSizeMegabytes': 'MB',
      }[key]!;

  String uk(String key) => {
        'chatSizeBytes': 'байт',
        'chatSizeKilobytes': 'КБ',
        'chatSizeMegabytes': 'МБ',
      }[key]!;

  group('PrivateAttachmentSizeFormatter', () {
    test('nonpositive and invalid values are empty', () {
      for (final value in [null, '', 'unknown', 0, -1]) {
        expect(
          PrivateAttachmentSizeFormatter.format(value, en),
          '',
        );
      }
    });

    test('formats bytes and kilobytes at boundaries', () {
      expect(PrivateAttachmentSizeFormatter.format(1, en), '1 B');
      expect(PrivateAttachmentSizeFormatter.format(1023, en), '1023 B');
      expect(PrivateAttachmentSizeFormatter.format(1024, en), '1.0 KB');
      expect(PrivateAttachmentSizeFormatter.format(1536, en), '1.5 KB');
      expect(PrivateAttachmentSizeFormatter.format('1536', en), '1.5 KB');
      expect(
        PrivateAttachmentSizeFormatter.format(102400, en),
        '100 KB',
      );
    });

    test('formats megabytes', () {
      expect(
        PrivateAttachmentSizeFormatter.format(1048576, en),
        '1.0 MB',
      );
      expect(
        PrivateAttachmentSizeFormatter.format(104857600, en),
        '100 MB',
      );
    });

    test('uses caller supplied language labels', () {
      expect(
        PrivateAttachmentSizeFormatter.format(1024, uk),
        '1.0 КБ',
      );
      expect(
        PrivateAttachmentSizeFormatter.format(1, uk),
        '1 байт',
      );
    });
  });
}