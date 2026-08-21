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

  bool get isProduction => environment == AppEnvironment.production;

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
