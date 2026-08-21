import 'dart:convert';

import 'package:chetiwa/core/location/chetiwa_location_repository.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/device_location_provider.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/core/network/chetiwa_api_client.dart';
import 'package:chetiwa/features/forecast/data/cache/forecast_cache_data_source.dart';
import 'package:chetiwa/features/forecast/data/repositories/chetiwa_forecast_repository.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/radar/data/cache/radar_cache_data_source.dart';
import 'package:chetiwa/features/radar/data/repositories/chetiwa_radar_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('API client keeps a private installation id and reuses ETags', () async {
    var calls = 0;
    String? installationId;
    final client = MockClient((request) async {
      calls++;
      final currentId = request.headers['x-chetiwa-device-id'];
      expect(currentId, matches(RegExp(r'^[a-f0-9]{32}$')));
      installationId ??= currentId;
      expect(currentId, installationId);
      if (calls == 2) {
        expect(request.headers['if-none-match'], '"forecast-v1"');
        return http.Response('', 304);
      }
      return http.Response(
        jsonEncode(<String, Object?>{
          'data': <String, Object?>{'value': 42},
          'meta': <String, Object?>{'generatedAt': '2026-08-20T18:00:00.000Z'},
        }),
        200,
        headers: const <String, String>{'etag': '"forecast-v1"'},
      );
    });
    final api = ChetiwaApiClient(
      baseUri: Uri.parse('https://api.chetiwa.test'),
      client: client,
    );

    expect((await api.getData('/v1/forecast'))['value'], 42);
    expect((await api.getData('/v1/forecast'))['value'], 42);
    expect(calls, 2);
  });

  test('forecast repository maps the stable Chetiwa contract', () async {
    final repository = ChetiwaForecastRepository(
      api: _apiFor('/v1/forecast', _forecastData),
      cache: const ForecastCacheDataSource(),
    );

    final forecast = await repository.getForecast(Coordinates.paris);

    expect(forecast.locationName, 'Paris, France');
    expect(forecast.timeZone, 'Europe/Paris');
    expect(forecast.updatedAt, DateTime.utc(2026, 8, 20, 18));
    expect(forecast.points.single.rateMmPerHour, 1.2);
    expect(forecast.brief.type, WeatherBriefType.raining);
    expect(forecast.hourly.single.precipitationProbability, 80);
    expect(forecast.daily.single.temperatureMax, 24);
    expect(forecast.providerName, 'open-meteo via Chetiwa');
  });

  test('radar repository maps observation and nowcast frames', () async {
    final repository = ChetiwaRadarRepository(
      api: _apiFor('/v1/radar/frames', <String, Object?>{
        'frames': <Object?>[
          <String, Object?>{
            'time': '2026-08-20T17:50:00.000Z',
            'kind': 'observation',
            'tileUrlTemplate': 'https://tiles.test/past/{z}/{x}/{y}.png',
          },
          <String, Object?>{
            'time': '2026-08-20T18:00:00.000Z',
            'kind': 'nowcast',
            'tileUrlTemplate': 'https://tiles.test/future/{z}/{x}/{y}.png',
          },
        ],
        'provider': <String, Object?>{'id': 'licensed-radar'},
      }),
      cache: const RadarCacheDataSource(),
    );

    final frames = await repository.getFrames(Coordinates.paris);

    expect(frames, hasLength(2));
    expect(frames.first.isObservation, isTrue);
    expect(frames.last.isNowcast, isTrue);
    expect(frames.last.progress, 1);
    expect(frames.last.providerName, 'licensed-radar via Chetiwa');
  });

  test('location repository maps worldwide backend search results', () async {
    final repository = ChetiwaLocationRepository(
      api: _apiFor('/v1/locations/search', <String, Object?>{
        'locations': <Object?>[
          <String, Object?>{
            'name': 'Tokyo',
            'country': 'Japon',
            'administrativeArea': 'Tokyo',
            'latitude': 35.6762,
            'longitude': 139.6503,
            'timeZone': 'Asia/Tokyo',
          },
        ],
      }),
      deviceLocationProvider: const _FakeLocationProvider(),
    );

    final results = await repository.search('Tokyo');

    expect(results.single.city, 'Tokyo');
    expect(results.single.country, 'Japon');
    expect(results.single.coordinates.longitude, 139.6503);
  });
}

ChetiwaApiClient _apiFor(String path, Map<String, Object?> data) =>
    ChetiwaApiClient(
      baseUri: Uri.parse('https://api.chetiwa.test'),
      client: MockClient((request) async {
        expect(request.url.path, path);
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': data,
            'meta': <String, Object?>{
              'generatedAt': '2026-08-20T18:00:00.000Z',
            },
          }),
          200,
        );
      }),
    );

const _forecastData = <String, Object?>{
  'location': <String, Object?>{
    'latitude': 48.8566,
    'longitude': 2.3522,
    'timeZone': 'Europe/Paris',
    'utcOffsetSeconds': 7200,
  },
  'updatedAt': '2026-08-20T18:00:00.000Z',
  'current': <String, Object?>{
    'temperatureCelsius': 22.4,
    'weatherCode': 61,
    'precipitationMm': 0.3,
    'windKph': 16.0,
  },
  'precipitation15m': <Object?>[
    <String, Object?>{
      'time': '2026-08-20T18:00:00.000Z',
      'amountMm': 0.3,
      'rateMmPerHour': 1.2,
    },
  ],
  'hourly': <Object?>[
    <String, Object?>{
      'time': '2026-08-20T18:00:00.000Z',
      'temperatureCelsius': 22.4,
      'weatherCode': 61,
      'precipitationProbability': 80,
      'precipitationMm': 0.8,
      'windKph': 16.0,
    },
  ],
  'daily': <Object?>[
    <String, Object?>{
      'date': '2026-08-20T00:00:00.000Z',
      'weatherCode': 61,
      'temperatureMax': 24.0,
      'temperatureMin': 17.0,
      'precipitationProbability': 80,
      'sunrise': '2026-08-20T04:50:00.000Z',
      'sunset': '2026-08-20T19:55:00.000Z',
    },
  ],
  'provider': <String, Object?>{'id': 'open-meteo'},
};

final class _FakeLocationProvider implements DeviceLocationProvider {
  const _FakeLocationProvider();

  @override
  Future<DeviceLocationFix> getCurrentLocationFix() async =>
      const DeviceLocationFix(
        coordinates: Coordinates.paris,
        acquisition: LocationAcquisition.precise,
      );

  @override
  Future<bool> openRecovery(LocationRecoveryAction action) async => true;
}
