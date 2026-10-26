import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/app_update_service.dart';

void main() {
  const manifest = <String, dynamic>{
    'schemaVersion': 1,
    'publishedAt': '2026-10-11T10:00:00Z',
    'platforms': <String, dynamic>{
      'android': <String, dynamic>{
        'version': '1.8.1',
        'build': 4236,
        'minimumSupportedBuild': 4200,
        'downloadUrl': 'https://fenyvo.com/download/Fenyvo-1.8.1-arm64.apk',
        'sha256': 'ABCDEF',
        'sizeBytes': 123,
        'notes': <String, dynamic>{
          'ru': <String>['Уведомления об обновлениях'],
          'en': <String>['Update notifications'],
        },
      },
    },
  };

  test('parses trusted Android release metadata', () {
    final release = AppRelease.fromManifest(manifest, 'android');
    expect(release.build, 4236);
    expect(release.minimumSupportedBuild, 4200);
    expect(release.notesFor('ru-RU'), ['Уведомления об обновлениях']);
    expect(release.notesFor('de-DE'), ['Update notifications']);
  });

  test('classifies optional and required updates by build number', () {
    final release = AppRelease.fromManifest(manifest, 'android');
    expect(release.isNewerThan(4233), isTrue);
    expect(release.isRequiredFor(4199), isTrue);
    expect(release.isRequiredFor(4200), isFalse);
  });

  test('rejects a download hosted outside fenyvo.com', () {
    final android = Map<String, dynamic>.from(
      (manifest['platforms']! as Map<String, dynamic>)['android']!
          as Map<String, dynamic>,
    );
    android['downloadUrl'] = 'https://example.com/fake.apk';
    final unsafe = <String, dynamic>{
      ...manifest,
      'platforms': <String, dynamic>{'android': android},
    };
    expect(
      () => AppRelease.fromManifest(unsafe, 'android'),
      throwsFormatException,
    );
  });
}
