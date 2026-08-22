import 'dart:io';

enum AppEnvironment {
  local,
  staging,
  production;

  static AppEnvironment parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'local' => local,
        'staging' => staging,
        'production' || 'prod' => production,
        _ => throw FormatException('Unsupported CHETIWA_ENV: $value'),
      };
}

final class RuntimeConfig {
  const RuntimeConfig({
    required this.environment,
    required this.port,
    required this.googleCloudProject,
    required this.openMeteoForecastUri,
    required this.openMeteoGeocodingUri,
    required this.openMeteoApiKey,
    required this.radarMetadataUri,
    required this.reverseGeocodingUri,
    required this.arcGisApiKey,
    required this.radarEnabled,
    required this.radarFreeSessions,
    required this.radarPremiumSessions,
    required this.radarTileUrlTemplate,
    required this.sharedCounterUrl,
    required this.monthlyBudgetCents,
    required this.radarTileCostCents,
    required this.globalKillSwitch,
    required this.publicBaseUrl,
    required this.internalMetricsToken,
  });

  factory RuntimeConfig.fromEnvironment([Map<String, String>? values]) {
    final source = values ?? Platform.environment;
    final environment = AppEnvironment.parse(source['CHETIWA_ENV'] ?? 'local');
    final port = int.tryParse(source['PORT'] ?? '8080');
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('PORT must be between 1 and 65535');
    }

    final rawProject = source['GOOGLE_CLOUD_PROJECT']?.trim();
    final googleCloudProject = rawProject == null || rawProject.isEmpty
        ? null
        : rawProject;
    if (environment != AppEnvironment.local && googleCloudProject == null) {
      throw StateError(
        'GOOGLE_CLOUD_PROJECT is required outside the local environment',
      );
    }

    Uri readUri(String key, String fallback) {
      final value = source[key]?.trim();
      final uri = Uri.tryParse(
        value == null || value.isEmpty ? fallback : value,
      );
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw FormatException('$key must be an absolute HTTP(S) URL');
      }
      if (uri.scheme != 'https' &&
          !(environment == AppEnvironment.local && uri.scheme == 'http')) {
        throw FormatException('$key must use HTTPS outside local development');
      }
      return uri;
    }

    return RuntimeConfig(
      environment: environment,
      port: port,
      googleCloudProject: googleCloudProject,
      openMeteoForecastUri: readUri(
        'OPEN_METEO_FORECAST_URL',
        'https://api.open-meteo.com/v1/forecast',
      ),
      openMeteoGeocodingUri: readUri(
        'OPEN_METEO_GEOCODING_URL',
        'https://geocoding-api.open-meteo.com/v1/search',
      ),
      openMeteoApiKey: _optional(source['OPEN_METEO_API_KEY']),
      radarMetadataUri: readUri(
        'RADAR_METADATA_URL',
        'https://api.rainviewer.com/public/weather-maps.json',
      ),
      reverseGeocodingUri: readUri(
        'REVERSE_GEOCODING_URL',
        'https://geocode-api.arcgis.com/arcgis/rest/services/World/GeocodeServer/reverseGeocode',
      ),
      arcGisApiKey: _optional(source['ARCGIS_API_KEY']),
      radarEnabled: _boolean(source['RADAR_ENABLED'], fallback: true),
      radarFreeSessions: _positiveInt(
        source['RADAR_FREE_SESSIONS'],
        fallback: 20,
      ),
      radarPremiumSessions: _positiveInt(
        source['RADAR_PREMIUM_SESSIONS'],
        fallback: 200,
      ),
      radarTileUrlTemplate: _optionalUrlTemplate(
        source['RADAR_TILE_URL_TEMPLATE'],
      ),
      sharedCounterUrl: _optionalUrl(source['SHARED_COUNTER_URL']),
      monthlyBudgetCents: _positiveInt(
        source['MONTHLY_BUDGET_CENTS'],
        fallback: 10000,
      ),
      radarTileCostCents: _nonNegativeInt(
        source['RADAR_TILE_COST_CENTS'],
        fallback: 1,
      ),
      globalKillSwitch: _boolean(source['GLOBAL_KILL_SWITCH'], fallback: false),
      publicBaseUrl: _optionalUrl(source['PUBLIC_BASE_URL']),
      internalMetricsToken: _optional(source['INTERNAL_METRICS_TOKEN']),
    );
  }

  final AppEnvironment environment;
  final int port;
  final String? googleCloudProject;
  final Uri openMeteoForecastUri;
  final Uri openMeteoGeocodingUri;
  final String? openMeteoApiKey;
  final Uri radarMetadataUri;
  final Uri reverseGeocodingUri;
  final String? arcGisApiKey;
  final bool radarEnabled;
  final int radarFreeSessions;
  final int radarPremiumSessions;
  final String? radarTileUrlTemplate;
  final Uri? sharedCounterUrl;
  final int monthlyBudgetCents;
  final int radarTileCostCents;
  final bool globalKillSwitch;
  final Uri? publicBaseUrl;
  final String? internalMetricsToken;

  bool get isProduction => environment == AppEnvironment.production;

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Uri? _optionalUrl(String? value) {
    final normalized = _optional(value);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw FormatException('URL must be absolute: $value');
    }
    return uri;
  }

  static String? _optionalUrlTemplate(String? value) {
    final normalized = _optional(value);
    if (normalized == null) return null;
    final uri = _optionalUrl(normalized);
    return uri?.toString();
  }

  static bool _boolean(String? value, {required bool fallback}) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return fallback;
    if (normalized == 'true' || normalized == '1' || normalized == 'on') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'off') {
      return false;
    }
    throw FormatException('Invalid boolean value: $value');
  }

  static int _positiveInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    if (parsed < 1) throw FormatException('Value must be positive: $value');
    return parsed;
  }

  static int _nonNegativeInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    if (parsed < 0) throw FormatException('Value must not be negative: $value');
    return parsed;
  }
}
