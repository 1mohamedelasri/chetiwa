import 'package:chetiwa/core/app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test(
    'reads the version and build number from the installed package',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Chetiwa',
        packageName: 'com.ezplatforms.chetiwa',
        version: '1.0.0',
        buildNumber: '7',
        buildSignature: '',
      );

      expect(await AppVersion.displayLabel(), '1.0.0 (7)');
    },
  );
}
