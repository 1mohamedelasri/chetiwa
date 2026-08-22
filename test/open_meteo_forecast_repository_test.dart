import 'dart:convert';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/features/forecast/data/cache/forecast_cache_data_source.dart';
import 'package:chetiwa/features/forecast/data/providers/open_meteo_forecast_provider.dart';
import 'package:chetiwa/features/forecast/data/repositories/open_meteo_forecast_repository.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('retries transient server failures before returning data', () async {
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      if (attempts < 3) return http.Response('temporarily unavailable', 503);
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final result = await OpenMeteoForecastProvider(
      client,
    ).fetch(Coordinates.paris);

    expect(result['ok'], isTrue);
    expect(attempts, 3);
    client.close();
  });

  test(
    'maps current, 15-minute, hourly and daily data for selected city',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, contains('open-meteo.com'));
        expect(request.url.path, '/v1/meteofrance');
        expect(request.url.queryParameters['forecast_minutely_15'], '96');
        expect(request.url.queryParameters['past_minutely_15'], '8');
        return http.Response(
          jsonEncode({
            'timezone': 'Europe/Paris',
            'utc_offset_seconds': 7200,
            'current': {
              'time': '2026-08-18T10:00',
              'temperature_2m': 19.4,
              'weather_code': 2,
              'precipitation': 0,
              'wind_speed_10m': 11.2,
            },
            'minutely_15': {
              'time': [
                '2026-08-18T10:00',
                '2026-08-18T10:15',
                '2026-08-18T10:30',
                '2026-08-18T10:45',
              ],
              'precipitation': [0, 0.25, 0.4, 0],
            },
            'hourly': {
              'time': ['2026-08-18T10:00', '2026-08-18T11:00'],
              'temperature_2m': [19.4, 20.1],
              'weather_code': [2, 61],
              'precipitation_probability': [10, 75],
              'precipitation': [0, 0.8],
              'wind_speed_10m': [11.2, 12.4],
            },
            'daily': {
              'time': ['2026-08-18'],
              'weather_code': [61],
              'temperature_2m_max': [24.2],
              'temperature_2m_min': [15.8],
              'precipitation_probability_max': [75],
              'sunrise': ['2026-08-18T06:42'],
              'sunset': ['2026-08-18T21:04'],
            },
          }),
          200,
        );
      });
      final repository = OpenMeteoForecastRepository(
        provider: OpenMeteoForecastProvider(client),
        cache: const ForecastCacheDataSource(),
      );

      final coordinates = LocationCatalog.locations[1].coordinates;
      final forecast = await repository.getForecast(coordinates);
      final cached = await repository.getCachedForecast(coordinates);

      expect(forecast.locationName, 'Clichy, France');
      expect(forecast.providerName, 'Météo-France AROME via Open-Meteo');
      expect(forecast.timeZone, 'Europe/Paris');
      expect(forecast.updatedAt, DateTime.utc(2026, 8, 18, 8));
      expect(forecast.points[1].time, DateTime.utc(2026, 8, 18, 8, 15));
      expect(forecast.currentWeatherCode, 2);
      expect(forecast.points[1].rateMmPerHour, 1);
      expect(forecast.points[1].intensity, RainIntensity.moderate);
      expect(forecast.brief.type, WeatherBriefType.imminent);
      expect(forecast.brief.headline, 'Pluie dans 15 min');
      expect(forecast.hourly, hasLength(2));
      expect(forecast.hourly.last.precipitationProbability, 75);
      expect(forecast.daily.single.temperatureMax, 24.2);
      expect(cached?.forecast.locationName, forecast.locationName);
      expect(cached?.forecast.timeZone, forecast.timeZone);
      expect(cached?.forecast.updatedAt, forecast.updatedAt);
      expect(cached?.forecast.points, forecast.points);
      expect(cached?.forecast.hourly, forecast.hourly);
      expect(cached?.forecast.daily, forecast.daily);
      client.close();
    },
  );
}
