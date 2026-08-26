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

enum RadarProvider {
  librewxr,
  rainViewer,
  configured;

  static RadarProvider parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'librewxr' => librewxr,
        'rainviewer' => rainViewer,
        'configured' || 'custom' => configured,
        _ => throw FormatException('Unsupported RADAR_PROVIDER: $value'),
      };
}

final class RuntimeConfig {
  const RuntimeConfig({
    required this.environment,
    required this.port,
    required this.googleCloudProject,
    required this.firestoreDatabaseId,
    required this.openMeteoForecastUri,
    required this.openMeteoMeteoFranceUri,
    required this.openMeteoGeocodingUri,
    required this.openMeteoApiKey,
    required this.radarProvider,
    required this.radarMetadataUri,
    required this.reverseGeocodingUri,
    required this.arcGisApiKey,
    required this.radarEnabled,
    required this.radarQuotaEnforced,
    required this.radarFreeSessions,
    required this.radarPremiumSessions,
    required this.radarTileUrlTemplate,
    required this.sharedCounterUrl,
    required this.monthlyBudgetCents,
    required this.radarTileCostCents,
    required this.globalKillSwitch,
    required this.premiumEnabled,
    required this.premiumRolloutPercent,
    required this.premiumRadarModelEnabled,
    required this.adsEnabled,
    required this.analyticsConsentPromptEnabled,
    required this.publicBaseUrl,
    required this.internalMetricsToken,
    required this.rainAlertsEnabled,
    required this.rainAlertsSendEnabled,
    required this.rainAlertCellSizeDegrees,
    required this.rainAlertMaxConcurrentCells,
    required this.rainAlertSoftBudgetCents,
    required this.rainAlertHardBudgetCents,
    required this.rainAlertBudgetCurrency,
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

    final radarEnabled = _boolean(source['RADAR_ENABLED'], fallback: true);
    final radarProvider = RadarProvider.parse(
      source['RADAR_PROVIDER'] ?? 'librewxr',
    );
    final publicBaseUrl = _optionalUrl(source['PUBLIC_BASE_URL']);
    if (environment == AppEnvironment.production && radarEnabled) {
      if (publicBaseUrl == null) {
        throw StateError(
          'PUBLIC_BASE_URL is required when radar is enabled in production',
        );
      }
      if (publicBaseUrl.scheme != 'https' ||
          _isPrivateOrLoopbackHost(publicBaseUrl.host)) {
        throw StateError(
          'PUBLIC_BASE_URL must be a public HTTPS URL in production',
        );
      }
    }

    final rainAlertSoftBudgetCents = _positiveInt(
      source['RAIN_ALERT_SOFT_BUDGET_CENTS'],
      fallback: 2500,
    );
    final rainAlertHardBudgetCents = _positiveInt(
      source['RAIN_ALERT_HARD_BUDGET_CENTS'],
      fallback: 5000,
    );
    if (rainAlertHardBudgetCents <= rainAlertSoftBudgetCents) {
      throw const FormatException(
        'RAIN_ALERT_HARD_BUDGET_CENTS must exceed the soft budget',
      );
    }

    return RuntimeConfig(
      environment: environment,
      port: port,
      googleCloudProject: googleCloudProject,
      firestoreDatabaseId:
          _optional(source['FIRESTORE_DATABASE_ID']) ?? '(default)',
      openMeteoForecastUri: readUri(
        'OPEN_METEO_FORECAST_URL',
        'https://api.open-meteo.com/v1/forecast',
      ),
      openMeteoMeteoFranceUri: readUri(
        'OPEN_METEO_METEOFRANCE_URL',
        'https://api.open-meteo.com/v1/meteofrance',
      ),
      openMeteoGeocodingUri: readUri(
        'OPEN_METEO_GEOCODING_URL',
        'https://geocoding-api.open-meteo.com/v1/search',
      ),
      openMeteoApiKey: _optional(source['OPEN_METEO_API_KEY']),
      radarProvider: radarProvider,
      radarMetadataUri: readUri(
        'RADAR_METADATA_URL',
        'https://api.librewxr.net/public/weather-maps.json',
      ),
      reverseGeocodingUri: readUri(
        'REVERSE_GEOCODING_URL',
        'https://geocode-api.arcgis.com/arcgis/rest/services/World/GeocodeServer/reverseGeocode',
      ),
      arcGisApiKey: _optional(source['ARCGIS_API_KEY']),
      radarEnabled: radarEnabled,
      radarQuotaEnforced: _boolean(
        source['RADAR_QUOTA_ENFORCED'],
        fallback: false,
      ),
      radarFreeSessions: _positiveInt(
        source['RADAR_FREE_SESSIONS'],
        fallback: 20,
      ),
      radarPremiumSessions: _positiveInt(
        source['RADAR_PREMIUM_SESSIONS'],
        fallback: 200,
      ),
      // LibreWXR deliberately mirrors the RainViewer metadata format. Keeping
      // the origin template here (rather than in the mobile client) means the
      // public API can cache, meter and replace it without an app release.
      radarTileUrlTemplate: _optionalUrlTemplate(
        source['RADAR_TILE_URL_TEMPLATE'] ??
            'https://api.librewxr.net{frame}/256/{z}/{x}/{y}/14/1_0.png?presentation=crisp-v2',
      ),
      sharedCounterUrl: _optionalUrl(source['SHARED_COUNTER_URL']),
      monthlyBudgetCents: _positiveInt(
        source['MONTHLY_BUDGET_CENTS'],
        fallback: 10000,
      ),
      radarTileCostCents: _nonNegativeInt(
        source['RADAR_TILE_COST_CENTS'],
        // LibreWXR's public beta endpoint has no per-tile charge. This is an
        // origin-provider estimate only; Cloud Run/network spending is
        // monitored separately and must not falsely kill free radar traffic.
        fallback: 0,
      ),
      globalKillSwitch: _boolean(source['GLOBAL_KILL_SWITCH'], fallback: false),
      premiumEnabled: _boolean(source['PREMIUM_ENABLED'], fallback: false),
      premiumRolloutPercent: _percentage(
        source['PREMIUM_ROLLOUT_PERCENT'],
        fallback: 0,
      ),
      premiumRadarModelEnabled: _boolean(
        source['PREMIUM_RADAR_MODEL_ENABLED'],
        fallback: false,
      ),
      adsEnabled: _boolean(source['ADS_ENABLED'], fallback: false),
      analyticsConsentPromptEnabled: _boolean(
        source['ANALYTICS_CONSENT_PROMPT_ENABLED'],
        fallback: false,
      ),
      publicBaseUrl: publicBaseUrl,
      internalMetricsToken: _optional(source['INTERNAL_METRICS_TOKEN']),
      rainAlertsEnabled: _boolean(
        source['RAIN_ALERTS_ENABLED'],
        fallback: false,
      ),
      rainAlertsSendEnabled: _boolean(
        source['RAIN_ALERTS_SEND_ENABLED'],
        fallback: false,
      ),
      rainAlertCellSizeDegrees: _positiveDouble(
        source['RAIN_ALERT_CELL_SIZE_DEGREES'],
        fallback: 0.05,
      ),
      rainAlertMaxConcurrentCells: _positiveInt(
        source['RAIN_ALERT_MAX_CONCURRENT_CELLS'],
        fallback: 8,
      ),
      rainAlertSoftBudgetCents: rainAlertSoftBudgetCents,
      rainAlertHardBudgetCents: rainAlertHardBudgetCents,
      rainAlertBudgetCurrency:
          (_optional(source['RAIN_ALERT_BUDGET_CURRENCY']) ?? 'EUR')
              .toUpperCase(),
    );
  }

  final AppEnvironment environment;
  final int port;
  final String? googleCloudProject;
  final String firestoreDatabaseId;
  final Uri openMeteoForecastUri;
  final Uri openMeteoMeteoFranceUri;
  final Uri openMeteoGeocodingUri;
  final String? openMeteoApiKey;
  final RadarProvider radarProvider;
  final Uri radarMetadataUri;
  final Uri reverseGeocodingUri;
  final String? arcGisApiKey;
  final bool radarEnabled;
  final bool radarQuotaEnforced;
  final int radarFreeSessions;
  final int radarPremiumSessions;
  final String? radarTileUrlTemplate;
  final Uri? sharedCounterUrl;
  final int monthlyBudgetCents;
  final int radarTileCostCents;
  final bool globalKillSwitch;
  final bool premiumEnabled;
  final int premiumRolloutPercent;
  final bool premiumRadarModelEnabled;
  final bool adsEnabled;
  final bool analyticsConsentPromptEnabled;
  final Uri? publicBaseUrl;
  final String? internalMetricsToken;
  final bool rainAlertsEnabled;
  final bool rainAlertsSendEnabled;
  final double rainAlertCellSizeDegrees;
  final int rainAlertMaxConcurrentCells;
  final int rainAlertSoftBudgetCents;
  final int rainAlertHardBudgetCents;
  final String rainAlertBudgetCurrency;

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
    const placeholders = <String>['{frame}', '{z}', '{x}', '{y}'];
    if (placeholders.any((placeholder) => !normalized.contains(placeholder))) {
      throw FormatException(
        'URL template must contain {frame}, {z}, {x} and {y}: $value',
      );
    }
    // Validate a concrete URL but preserve the raw template. Calling
    // Uri.toString() on the template percent-encodes braces (`%7Bz%7D`), so
    // ProviderGateway can no longer replace them and requests the wrong path.
    final concrete = normalized
        .replaceAll('{frame}', '/frame')
        .replaceAll('{z}', '7')
        .replaceAll('{x}', '64')
        .replaceAll('{y}', '44');
    final uri = Uri.tryParse(concrete);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw FormatException(
        'URL template must produce an absolute URL: $value',
      );
    }
    return normalized;
  }

  static bool _isPrivateOrLoopbackHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' ||
        normalized == '0.0.0.0' ||
        normalized == '::1' ||
        normalized.endsWith('.localhost')) {
      return true;
    }
    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return bytes[0] == 10 ||
          bytes[0] == 127 ||
          bytes[0] == 192 && bytes[1] == 168 ||
          bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31;
    }
    return false;
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

  static double _positiveDouble(String? value, {required double fallback}) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    if (!parsed.isFinite || parsed <= 0) {
      throw FormatException('Value must be a positive number: $value');
    }
    return parsed;
  }

  static int _nonNegativeInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    if (parsed < 0) throw FormatException('Value must not be negative: $value');
    return parsed;
  }

  static int _percentage(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    if (parsed < 0 || parsed > 100) {
      throw FormatException('Value must be between 0 and 100: $value');
    }
    return parsed;
  }
}
