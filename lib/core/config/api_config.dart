abstract final class ApiConfig {
  static const appEnvironment = String.fromEnvironment(
    'CHETIWA_ENV',
    defaultValue: 'development',
  );

  /// Development-only switch used to exercise the real OS notification path
  /// without waiting for weather. It is ignored by production builds.
  static const notificationTestMode = bool.fromEnvironment(
    'CHETIWA_NOTIFICATION_TEST_MODE',
    defaultValue: false,
  );
  static const chetiwaApiBaseUrl = String.fromEnvironment(
    'CHETIWA_API_BASE_URL',
  );
  static const _directFallbackRequested = bool.fromEnvironment(
    'CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK',
    defaultValue: true,
  );
  static const _premiumRadarTestRequested = bool.fromEnvironment(
    'CHETIWA_PREMIUM_RADAR_TEST_MODE',
    defaultValue: false,
  );
  static const openMeteoApiKey = String.fromEnvironment('OPEN_METEO_API_KEY');

  static String get openMeteoHost => openMeteoApiKey.isEmpty
      ? 'api.open-meteo.com'
      : 'customer-api.open-meteo.com';

  static String get openMeteoGeocodingHost => openMeteoApiKey.isEmpty
      ? 'geocoding-api.open-meteo.com'
      : 'customer-geocoding-api.open-meteo.com';

  /// Public beta endpoint used only by the development direct-provider path.
  /// Production builds must use CHETIWA_API_BASE_URL instead.
  static const radarMetadataUrl =
      'https://radar.ezplatforms.com/public/weather-maps.json';

  @Deprecated('Use radarMetadataUrl')
  static const rainViewerMetadataUrl = radarMetadataUrl;

  static bool get isProduction => appEnvironment == 'production';
  static bool get usesNotificationTestForecast =>
      notificationTestMode && !isProduction;
  static bool get usesChetiwaBackend => chetiwaApiBaseUrl.trim().isNotEmpty;
  static bool get allowsDirectProviderFallback =>
      !isProduction && _directFallbackRequested;

  /// Developer-only entitlement used to inspect the real +60–120 minute
  /// LibreWXR model frames before store products are available. A production
  /// build always ignores the define, even if it is accidentally supplied.
  static bool get premiumRadarTestMode =>
      !isProduction && _premiumRadarTestRequested;

  static Uri requireChetiwaApiBaseUri() {
    final value = chetiwaApiBaseUrl.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('CHETIWA_API_BASE_URL must be an absolute HTTP(S) URL');
    }
    if (isProduction && uri.scheme != 'https') {
      throw StateError('CHETIWA_API_BASE_URL must use HTTPS in production');
    }
    return uri;
  }
}
