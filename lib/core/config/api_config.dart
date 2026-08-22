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
  static const openMeteoApiKey = String.fromEnvironment('OPEN_METEO_API_KEY');
  static const arcGisApiKey = String.fromEnvironment('ARCGIS_API_KEY');

  static String get openMeteoHost => openMeteoApiKey.isEmpty
      ? 'api.open-meteo.com'
      : 'customer-api.open-meteo.com';

  static String get openMeteoGeocodingHost => openMeteoApiKey.isEmpty
      ? 'geocoding-api.open-meteo.com'
      : 'customer-geocoding-api.open-meteo.com';

  static const rainViewerMetadataUrl =
      'https://api.rainviewer.com/public/weather-maps.json';

  static bool get isProduction => appEnvironment == 'production';
  static bool get usesNotificationTestForecast =>
      notificationTestMode && !isProduction;
  static bool get usesChetiwaBackend => chetiwaApiBaseUrl.trim().isNotEmpty;
  static bool get allowsDirectProviderFallback =>
      !isProduction && _directFallbackRequested;

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
