import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/incoming_share_service.dart';

void main() {
  test('Accepts a single image share without disclosing its contents', () {
    final share = IncomingSharePayload.fromPlatform({
      'text': '',
      'images': [
        {
          'path': '/data/user/0/com.fenyvo.app/cache/incoming_share/shared_x.png',
          'fileName': 'shared_x.png',
          'mimeType': 'image/png',
        },
      ],
    });
    expect(share, isNotNull);
    expect(share!.images, hasLength(1));
    expect(share.images.single.mimeType, 'image/png');
  });

  test('Accepts a text-only share as an editable draft', () {
    final share = IncomingSharePayload.fromPlatform({
      'text': 'Hello FENYVO',
      'images': <Object>[],
    });
    expect(share?.text, 'Hello FENYVO');
    expect(share?.images, isEmpty);
  });

  test('Rejects empty and invalid image payloads', () {
    expect(IncomingSharePayload.fromPlatform({'text': '', 'images': []}), isNull);
    expect(IncomingSharePayload.fromPlatform({
      'text': '',
      'images': [
        {'path': '../unsafe', 'fileName': 'test.jpg', 'mimeType': 'image/jpeg'},
      ],
    }), isNull);
  });

  test('Rejects more than five images', () {
    final images = List.generate(6, (i) => {
      'path': '/private/fenyvo/share_$i.png',
      'fileName': 'share_$i.png',
      'mimeType': 'image/png',
    });
    expect(IncomingSharePayload.fromPlatform({'text': '', 'images': images}), isNull);
  });
}
