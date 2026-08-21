import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platforms declare network and foreground location permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.ACCESS_NETWORK_STATE'));
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    expect(infoPlist, contains('NSLocationWhenInUseUsageDescription'));
  });
}
