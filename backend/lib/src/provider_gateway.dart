import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'runtime_config.dart';

final class ProviderGateway {
  ProviderGateway({
    required RuntimeConfig config,
    http.Client? client,
    Future<void> Function(Duration duration)? delay,
  }) : _config = config,
       _client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  final RuntimeConfig _config;
  final http.Client _client;
  final Future<void> Function(Duration duration) _delay;

  Future<Map<String, Object?>> forecast({
    required double latitude,
    required double longitude,
  }) async {
    if (_config.isProduction && _config.openMeteoApiKey == null) {
      throw const ApiException(
        statusCode: 503,
        code: 'forecast_provider_not_configured',
        message: 'Commercial forecast credentials are not configured',
      );
    }
    final usesMeteoFranceNowcast = _isMetropolitanFrance(
      latitude: latitude,
      longitude: longitude,
    );
    final raw = await _getJson(
      (usesMeteoFranceNowcast
              ? _config.openMeteoMeteoFranceUri
              : _config.openMeteoForecastUri)
          .replace(
            queryParameters: <String, String>{
              'latitude': latitude.toString(),
              'longitude': longitude.toString(),
              'current':
                  'temperature_2m,weather_code,precipitation,wind_speed_10m',
              'minutely_15': 'precipitation,temperature_2m,wind_speed_10m',
              'hourly':
                  'temperature_2m,weather_code,precipitation_probability,precipitation,wind_speed_10m',
              'daily':
                  'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
              'forecast_minutely_15': '96',
              'past_minutely_15': '8',
              'forecast_days': '10',
              'timezone': 'auto',
              'timeformat': 'unixtime',
              if (_config.openMeteoApiKey case final key?) 'apikey': key,
            },
          ),
    );
    return _normalizeForecast(
      raw,
      latitude: latitude,
      longitude: longitude,
      providerId: usesMeteoFranceNowcast
          ? 'meteofrance-arome-15m-via-open-meteo'
          : 'open-meteo-best-match',
    );
  }

  Future<Map<String, Object?>> searchLocations({
    required String query,
    required String language,
    required int count,
  }) async {
    if (_config.isProduction && _config.openMeteoApiKey == null) {
      throw const ApiException(
        statusCode: 503,
        code: 'geocoding_provider_not_configured',
        message: 'Commercial geocoding credentials are not configured',
      );
    }
    final raw = await _getJson(
      _config.openMeteoGeocodingUri.replace(
        queryParameters: <String, String>{
          'name': query,
          'count': count.toString(),
          'language': language,
          'format': 'json',
          if (_config.openMeteoApiKey case final key?) 'apikey': key,
        },
      ),
    );
    final results = raw['results'];
    return <String, Object?>{
      'locations': results is List
          ? results
                .whereType<Map<String, dynamic>>()
                .map(_normalizeLocation)
                .whereType<Map<String, Object?>>()
                .toList(growable: false)
          : const <Object>[],
      'provider': const <String, Object?>{
        'id': 'open-meteo-geocoding',
        'kind': 'geocoding',
      },
    };
  }

  Future<Map<String, Object?>> reverseLocation({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final apiKey = _config.arcGisApiKey;
    if (apiKey == null) {
      throw const ApiException(
        statusCode: 503,
        code: 'reverse_geocoding_not_configured',
        message: 'Reverse geocoding credentials are not configured',
      );
    }
    final raw = await _getJson(
      _config.reverseGeocodingUri.replace(
        queryParameters: <String, String>{
          'f': 'json',
          'location': '$longitude,$latitude',
          'langCode': language,
          'token': apiKey,
        },
      ),
    );
    final address = raw['address'];
    final point = raw['location'];
    if (address is! Map<String, dynamic> || point is! Map<String, dynamic>) {
      throw const ApiException(
        statusCode: 502,
        code: 'invalid_reverse_geocoding_response',
        message: 'Reverse geocoding provider returned an invalid response',
      );
    }
    return <String, Object?>{
      'location': <String, Object?>{
        'name': address['City'] ?? address['District'] ?? address['Match_addr'],
        'country': address['CountryCode'] ?? address['CntryName'] ?? '',
        'administrativeArea': address['Region'] ?? address['RegionAbbr'],
        'latitude': (point['y'] as num?)?.toDouble() ?? latitude,
        'longitude': (point['x'] as num?)?.toDouble() ?? longitude,
      },
      'provider': const <String, Object?>{
        'id': 'arcgis-world-geocoding',
        'kind': 'reverse-geocoding',
      },
    };
  }

  Future<Map<String, Object?>> radarFrames({
    required double latitude,
    required double longitude,
  }) async {
    final usesRainViewer = _config.radarMetadataUri.host.contains(
      'rainviewer.com',
    );
    final usesLibreWxr = _config.radarMetadataUri.host.endsWith('librewxr.net');
    if (_config.isProduction && usesRainViewer) {
      throw const ApiException(
        statusCode: 503,
        code: 'radar_provider_not_configured',
        message: 'A licensed production radar provider is not configured',
      );
    }
    final raw = await _getJson(_config.radarMetadataUri);
    final host = raw['host'];
    final radar = raw['radar'];
    if (host is! String || radar is! Map<String, dynamic>) {
      throw const ApiException(
        statusCode: 502,
        code: 'invalid_radar_response',
        message: 'Radar provider returned incomplete metadata',
      );
    }
    final frames = <Map<String, Object?>>[];
    void appendFrames(Object? values, String kind) {
      if (values is! List) return;
      for (final item in values.whereType<Map<String, dynamic>>()) {
        final path = item['path'];
        final timestamp = item['time'];
        if (path is! String || timestamp is! num) continue;
        final frameId = base64Url.encode(utf8.encode(path)).replaceAll('=', '');
        final tileUrlTemplate = _config.publicBaseUrl == null
            ? '$host$path/256/{z}/{x}/{y}/${usesLibreWxr ? '10/1_1' : '2/1_0'}.png'
            : '${_config.publicBaseUrl}/v1/radar/tiles/$frameId/{z}/{x}/{y}';
        frames.add(<String, Object?>{
          'time': _isoFromEpoch(timestamp),
          'kind': kind,
          'tileUrlTemplate': tileUrlTemplate,
        });
      }
    }

    appendFrames(radar['past'], 'observation');
    // RainViewer stopped serving future frames in 2026. Keep the development
    // path truthful even if a legacy response happens to contain that field.
    if (!usesRainViewer) appendFrames(radar['nowcast'], 'nowcast');
    if (frames.isEmpty) {
      throw const ApiException(
        statusCode: 502,
        code: 'invalid_radar_response',
        message: 'Radar provider returned no usable frames',
      );
    }
    return <String, Object?>{
      'location': <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
      },
      'frames': frames,
      'provider': <String, Object?>{
        'id': usesRainViewer
            ? 'rainviewer-development'
            : usesLibreWxr
            ? 'librewxr'
            : 'configured-radar',
        'kind': 'radar',
      },
    };
  }

  Future<Uint8List> radarTile({
    required String frame,
    required int z,
    required int x,
    required int y,
  }) async {
    final template = _config.radarTileUrlTemplate;
    if (template == null) {
      throw const ApiException(
        statusCode: 503,
        code: 'radar_tile_provider_not_configured',
        message: 'A licensed radar tile provider is not configured',
      );
    }
    final uri = Uri.parse(
      template
          .replaceAll('{frame}', frame)
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y'),
    );
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: const <String, String>{'accept': 'image/png'})
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return Uint8List.fromList(response.bodyBytes);
        }
        if (response.statusCode < 500 && response.statusCode != 429) {
          throw ApiException(
            statusCode: 502,
            code: 'radar_tile_provider_rejected',
            message: 'Radar tile provider returned HTTP ${response.statusCode}',
          );
        }
        lastError = 'HTTP ${response.statusCode}';
      } on ApiException {
        rethrow;
      } on Object catch (error) {
        lastError = error;
      }
      if (attempt < 2) {
        await _delay(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    throw ApiException(
      statusCode: 503,
      code: 'radar_tile_provider_unavailable',
      message: 'Radar tile provider unavailable after retries: $lastError',
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .get(
              uri,
              headers: const <String, String>{'accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) return decoded;
          throw const FormatException('Expected a JSON object');
        }
        if (response.statusCode < 500 && response.statusCode != 429) {
          throw ApiException(
            statusCode: 502,
            code: 'provider_rejected_request',
            message: 'Provider returned HTTP ${response.statusCode}',
          );
        }
        lastError = 'HTTP ${response.statusCode}';
      } on ApiException {
        rethrow;
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      } on FormatException catch (error) {
        throw ApiException(
          statusCode: 502,
          code: 'invalid_provider_response',
          message: error.message,
        );
      }
      if (attempt < 2) {
        await _delay(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    throw ApiException(
      statusCode: 503,
      code: 'provider_unavailable',
      message: 'Provider unavailable after retries: $lastError',
    );
  }
}

/// AROME's operational high-resolution domain is metropolitan France and
/// nearby border areas. Overseas locations keep the global best-match route.
bool _isMetropolitanFrance({
  required double latitude,
  required double longitude,
}) => latitude >= 41 && latitude <= 52 && longitude >= -5.8 && longitude <= 10;

Map<String, Object?> _normalizeForecast(
  Map<String, dynamic> raw, {
  required double latitude,
  required double longitude,
  required String providerId,
}) {
  final current = _map(raw['current']);
  final minutely = _map(raw['minutely_15']);
  final hourly = _map(raw['hourly']);
  final daily = _map(raw['daily']);
  if (current['time'] is! num ||
      hourly['time'] is! List ||
      (hourly['time'] as List).isEmpty ||
      daily['time'] is! List ||
      (daily['time'] as List).isEmpty) {
    throw const ApiException(
      statusCode: 502,
      code: 'invalid_forecast_response',
      message: 'Forecast provider returned incomplete data',
    );
  }
  return <String, Object?>{
    'location': <String, Object?>{
      'latitude': latitude,
      'longitude': longitude,
      'timeZone': raw['timezone'] ?? 'Etc/UTC',
      'utcOffsetSeconds': (raw['utc_offset_seconds'] as num?)?.toInt() ?? 0,
    },
    'updatedAt': _isoFromEpoch(current['time']),
    'current': <String, Object?>{
      'temperatureCelsius': _double(current['temperature_2m']),
      'weatherCode': _integer(current['weather_code']),
      'precipitationMm': _double(current['precipitation']),
      'windKph': _double(current['wind_speed_10m']),
    },
    'precipitation15m': _zip(minutely, <String>['time', 'precipitation'])
        .map((row) {
          final amount = _double(row['precipitation']);
          return <String, Object?>{
            'time': _isoFromEpoch(row['time']),
            'amountMm': amount,
            'rateMmPerHour': amount * 4,
          };
        })
        .toList(growable: false),
    'hourly':
        _zip(hourly, <String>[
              'time',
              'temperature_2m',
              'weather_code',
              'precipitation_probability',
              'precipitation',
              'wind_speed_10m',
            ])
            .map(
              (row) => <String, Object?>{
                'time': _isoFromEpoch(row['time']),
                'temperatureCelsius': _double(row['temperature_2m']),
                'weatherCode': _integer(row['weather_code']),
                'precipitationProbability': _integer(
                  row['precipitation_probability'],
                ),
                'precipitationMm': _double(row['precipitation']),
                'windKph': _double(row['wind_speed_10m']),
              },
            )
            .toList(growable: false),
    'daily':
        _zip(daily, <String>[
              'time',
              'weather_code',
              'temperature_2m_max',
              'temperature_2m_min',
              'precipitation_probability_max',
              'sunrise',
              'sunset',
            ])
            .map(
              (row) => <String, Object?>{
                'date': _isoFromEpoch(row['time']),
                'weatherCode': _integer(row['weather_code']),
                'temperatureMax': _double(row['temperature_2m_max']),
                'temperatureMin': _double(row['temperature_2m_min']),
                'precipitationProbability': _integer(
                  row['precipitation_probability_max'],
                ),
                'sunrise': _isoFromEpoch(row['sunrise']),
                'sunset': _isoFromEpoch(row['sunset']),
              },
            )
            .toList(growable: false),
    'provider': <String, Object?>{'id': providerId, 'kind': 'model-forecast'},
  };
}

Map<String, Object?>? _normalizeLocation(Map<String, dynamic> raw) {
  final name = raw['name'];
  final latitude = raw['latitude'];
  final longitude = raw['longitude'];
  if (name is! String || latitude is! num || longitude is! num) return null;
  return <String, Object?>{
    'name': name,
    'country': raw['country'] ?? '',
    'administrativeArea': raw['admin1'],
    'latitude': latitude.toDouble(),
    'longitude': longitude.toDouble(),
    'timeZone': raw['timezone'],
  };
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<Map<String, Object?>> _zip(
  Map<String, dynamic> source,
  List<String> keys,
) {
  final lists = keys.map((key) => source[key]).whereType<List>().toList();
  if (lists.length != keys.length || lists.isEmpty) return const [];
  final count = lists
      .map((list) => list.length)
      .reduce((a, b) => a < b ? a : b);
  return List<Map<String, Object?>>.generate(
    count,
    (index) => <String, Object?>{
      for (var keyIndex = 0; keyIndex < keys.length; keyIndex++)
        keys[keyIndex]: lists[keyIndex][index],
    },
    growable: false,
  );
}

String _isoFromEpoch(Object? value) {
  final seconds = value is num ? value.toInt() : 0;
  return DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toIso8601String();
}

double _double(Object? value) => (value as num?)?.toDouble() ?? 0;

int _integer(Object? value) => (value as num?)?.toInt() ?? 0;
