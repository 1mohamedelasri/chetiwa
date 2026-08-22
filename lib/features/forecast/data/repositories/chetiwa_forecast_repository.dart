import '../../../../core/location/coordinates.dart';
import '../../../../core/network/chetiwa_api_client.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/weather/weather_data_health.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/repositories/forecast_repository.dart';
import '../../domain/services/rain_rate_scale.dart';
import '../../domain/services/weather_brief_builder.dart';
import '../cache/forecast_cache_data_source.dart';

final class ChetiwaForecastRepository implements ForecastRepository {
  const ChetiwaForecastRepository({
    required ChetiwaApiClient api,
    required ForecastCacheDataSource cache,
  }) : _api = api,
       _cache = cache;

  final ChetiwaApiClient _api;
  final ForecastCacheDataSource _cache;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) =>
      _cache.read(coordinates);

  @override
  Future<Forecast> getForecast(Coordinates coordinates) async {
    try {
      final data = await _api.getData(
        '/v1/forecast',
        query: _coordinateQuery(coordinates),
      );
      final forecast = _map(data, coordinates);
      await _cache.write(coordinates, forecast);
      return forecast;
    } on ChetiwaApiException catch (error) {
      throw WeatherDataException(
        error.isNetworkFailure
            ? WeatherDataIssue.offline
            : WeatherDataIssue.providerUnavailable,
        error.message,
      );
    } on FormatException {
      throw const WeatherDataException(
        WeatherDataIssue.invalidResponse,
        'Réponse Chetiwa invalide',
      );
    } on TypeError {
      throw const WeatherDataException(
        WeatherDataIssue.invalidResponse,
        'Réponse Chetiwa incomplète',
      );
    }
  }

  Forecast _map(Map<String, dynamic> data, Coordinates coordinates) {
    final location = data['location'] as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    final timeZone = location['timeZone'] as String? ?? 'Etc/UTC';
    final updatedAt = DateTime.parse(data['updatedAt'] as String).toUtc();
    final points = (data['precipitation15m'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((point) {
          final rate = (point['rateMmPerHour'] as num?)?.toDouble() ?? 0;
          return RainPoint(
            time: DateTime.parse(point['time'] as String).toUtc(),
            rateMmPerHour: rate,
            intensity: RainRateScale.intensityFor(rate),
          );
        })
        .toList(growable: false);
    final decisionPoints = points
        .where((point) => !point.time.isBefore(updatedAt))
        .toList(growable: false);
    final summary = WeatherBriefBuilder.build(
      now: updatedAt,
      points: decisionPoints,
      formatTime: (instant) => WeatherTimeZone.hourMinute(instant, timeZone),
    );
    final provider = data['provider'] as Map<String, dynamic>?;
    return Forecast(
      locationName: LocationCatalog.forCoordinates(coordinates).label,
      updatedAt: updatedAt,
      temperatureCelsius:
          (current['temperatureCelsius'] as num?)?.toDouble() ?? 0,
      windKph: (current['windKph'] as num?)?.toDouble() ?? 0,
      currentWeatherCode: (current['weatherCode'] as num?)?.toInt() ?? 0,
      utcOffsetSeconds: (location['utcOffsetSeconds'] as num?)?.toInt() ?? 0,
      timeZone: timeZone,
      providerName: '${provider?['id'] ?? 'weather'} via Chetiwa',
      brief: summary.brief,
      points: points,
      windows: summary.windows,
      hourly: _hourly(data['hourly'], updatedAt),
      daily: _daily(data['daily']),
    );
  }

  List<HourlyForecast> _hourly(Object? raw, DateTime updatedAt) =>
      (raw as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => HourlyForecast(
              time: DateTime.parse(item['time'] as String).toUtc(),
              temperatureCelsius:
                  (item['temperatureCelsius'] as num?)?.toDouble() ?? 0,
              weatherCode: (item['weatherCode'] as num?)?.toInt() ?? 0,
              precipitationProbability:
                  (item['precipitationProbability'] as num?)?.toInt() ?? 0,
              precipitationMm:
                  (item['precipitationMm'] as num?)?.toDouble() ?? 0,
              windKph: (item['windKph'] as num?)?.toDouble() ?? 0,
            ),
          )
          .where((item) => !item.time.isBefore(updatedAt))
          .toList(growable: false);

  List<DailyForecast> _daily(Object? raw) => (raw as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => DailyForecast(
          date: DateTime.parse(item['date'] as String).toUtc(),
          weatherCode: (item['weatherCode'] as num?)?.toInt() ?? 0,
          temperatureMax: (item['temperatureMax'] as num?)?.toDouble() ?? 0,
          temperatureMin: (item['temperatureMin'] as num?)?.toDouble() ?? 0,
          precipitationProbability:
              (item['precipitationProbability'] as num?)?.toInt() ?? 0,
          sunrise: DateTime.parse(item['sunrise'] as String).toUtc(),
          sunset: DateTime.parse(item['sunset'] as String).toUtc(),
        ),
      )
      .toList(growable: false);
}

Map<String, String> _coordinateQuery(Coordinates coordinates) =>
    <String, String>{
      'latitude': coordinates.latitude.toString(),
      'longitude': coordinates.longitude.toString(),
    };
