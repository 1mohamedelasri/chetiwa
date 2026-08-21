import 'package:package_info_plus/package_info_plus.dart';

/// Reads the version embedded in the installed Android/iOS application.
///
/// The value comes from `pubspec.yaml` (or from the build arguments used by
/// Flutter), so Settings cannot drift from the distributed build.
abstract final class AppVersion {
  static Future<String> displayLabel() async {
    final package = await PackageInfo.fromPlatform();
    return '${package.version} (${package.buildNumber})';
  }
}
