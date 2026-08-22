abstract final class AdMobConfig {
  static const androidBannerId = String.fromEnvironment(
    'CHETIWA_ADMOB_ANDROID_BANNER_ID',
  );
  static const iosBannerId = String.fromEnvironment(
    'CHETIWA_ADMOB_IOS_BANNER_ID',
  );

  static bool get isConfigured {
    if (androidBannerId.isEmpty && iosBannerId.isEmpty) return false;
    return true;
  }
}
