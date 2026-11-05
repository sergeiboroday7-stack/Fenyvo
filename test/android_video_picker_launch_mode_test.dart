import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android image picker requires compatible activity launch mode', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest.contains('android:launchMode="singleTask"'),
      isTrue,
      reason: 'MainActivity must use singleTask for Android media picker.',
    );

    expect(
      manifest.contains('android:launchMode="singleInstance"'),
      isFalse,
      reason: 'singleInstance breaks Android picker results.',
    );
  });
}