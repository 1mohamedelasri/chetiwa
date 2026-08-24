import '../../../../core/location/coordinates.dart';
import '../../../../core/time/weather_clock.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/repositories/forecast_repository.dart';
import '../../domain/services/weather_brief_builder.dart';
import '../../domain/services/rain_rate_scale.dart';
import '../cache/forecast_cache_data_source.dart';
import '../providers/open_meteo_forecast_provider.dart';

final class OpenMeteoForecastRepository implements ForecastRepository {
  const OpenMeteoForecastRepository({
    required OpenMeteoForecastProvider provider,
    required ForecastCacheDataSource cache,
  }) : _provider = provider,
       _cache = cache;

  final OpenMeteoForecastProvider _provider;
  final ForecastCacheDataSource _cache;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) =>
      _cache.read(coordinates);

  @override
  Future<Forecast> getForecast(Coordinates coordinates) async {
    final response = await _provider.fetch(coordinates);
    final forecast = _mapResponse(response, coordinates);
    await _cache.write(coordinates, forecast);
    return forecast;
  }

  Forecast _mapResponse(
    Map<String, dynamic> response,
    Coordinates coordinates,
  ) {
    final timeZone = response['timezone'] as String? ?? 'Etc/UTC';
    final current = response['current'] as Map<String, dynamic>;
    final minutely = response['minutely_15'] as Map<String, dynamic>;
    final times = minutely['time'] as List<dynamic>;
    final precipitation = minutely['precipitation'] as List<dynamic>;
    final count = times.length < precipitation.length
        ? times.length
        : precipitation.length;
    final points = List.generate(count, (index) {
      final amount = (precipitation[index] as num?)?.toDouble() ?? 0;
      final rate = amount * 4;
      return RainPoint(
        time: WeatherTimeZone.parseLocal(times[index] as String, timeZone),
        rateMmPerHour: rate,
        intensity: RainRateScale.intensityFor(rate),
      );
    }, growable: false);
    final updatedAt = WeatherTimeZone.parseLocal(
      current['time'] as String,
      timeZone,
    );
    final decisionPoints = points
        .where((point) => !point.time.isBefore(updatedAt))
        .toList(growable: false);
    final summary = WeatherBriefBuilder.build(
      now: updatedAt,
      points: decisionPoints,
      formatTime: WeatherTimeZone.displayHourMinute,
    );
    final hourly = _mapHourly(response['hourly'], updatedAt, timeZone);
    final daily = _mapDaily(response['daily'], timeZone);
    return Forecast(
      locationName: LocationCatalog.forCoordinates(coordinates).label,
      updatedAt: updatedAt,
      temperatureCelsius: (current['temperature_2m'] as num).toDouble(),
      windKph: (current['wind_speed_10m'] as num).toDouble(),
      utcOffsetSeconds: (response['utc_offset_seconds'] as num?)?.toInt() ?? 0,
      timeZone: timeZone,
      currentWeatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
      brief: summary.brief,
      points: points,
      windows: summary.windows,
      providerName: _provider.providerNameFor(coordinates),
      hourly: hourly,
      daily: daily,
    );
  }

  List<HourlyForecast> _mapHourly(
    Object? raw,
    DateTime updatedAt,
    String timeZone,
  ) {
    if (raw is! Map<String, dynamic>) return const [];
    final times = raw['time'] as List<dynamic>? ?? const [];
    final temperatures = raw['temperature_2m'] as List<dynamic>? ?? const [];
    final codes = raw['weather_code'] as List<dynamic>? ?? const [];
    final probabilities =
        raw['precipitation_probability'] as List<dynamic>? ?? const [];
    final precipitation = raw['precipitation'] as List<dynamic>? ?? const [];
    final wind = raw['wind_speed_10m'] as List<dynamic>? ?? const [];
    final count = [
      times.length,
      temperatures.length,
      codes.length,
      probabilities.length,
      precipitation.length,
      wind.length,
    ].reduce((a, b) => a < b ? a : b);
    return List.generate(
      count,
      (index) {
        final time = WeatherTimeZone.parseLocal(
          times[index] as String,
          timeZone,
        );
        return HourlyForecast(
          time: time,
          temperatureCelsius: (temperatures[index] as num?)?.toDouble() ?? 0,
          weatherCode: (codes[index] as num?)?.toInt() ?? 0,
          precipitationProbability:
              (probabilities[index] as num?)?.toInt() ?? 0,
          precipitationMm: (precipitation[index] as num?)?.toDouble() ?? 0,
          windKph: (wind[index] as num?)?.toDouble() ?? 0,
        );
      },
      growable: false,
    ).where((item) => !item.time.isBefore(updatedAt)).toList(growable: false);
  }

  List<DailyForecast> _mapDaily(Object? raw, String timeZone) {
    if (raw is! Map<String, dynamic>) return const [];
    final times = raw['time'] as List<dynamic>? ?? const [];
    final codes = raw['weather_code'] as List<dynamic>? ?? const [];
    final maximums = raw['temperature_2m_max'] as List<dynamic>? ?? const [];
    final minimums = raw['temperature_2m_min'] as List<dynamic>? ?? const [];
    final probabilities =
        raw['precipitation_probability_max'] as List<dynamic>? ?? const [];
    final sunrises = raw['sunrise'] as List<dynamic>? ?? const [];
    final sunsets = raw['sunset'] as List<dynamic>? ?? const [];
    final count = [
      times.length,
      codes.length,
      maximums.length,
      minimums.length,
      probabilities.length,
      sunrises.length,
      sunsets.length,
    ].reduce((a, b) => a < b ? a : b);
    return List.generate(
      count,
      (index) => DailyForecast(
        date: DateTime.parse(times[index] as String),
        weatherCode: (codes[index] as num?)?.toInt() ?? 0,
        temperatureMax: (maximums[index] as num?)?.toDouble() ?? 0,
        temperatureMin: (minimums[index] as num?)?.toDouble() ?? 0,
        precipitationProbability: (probabilities[index] as num?)?.toInt() ?? 0,
        sunrise: WeatherTimeZone.parseLocal(
          sunrises[index] as String,
          timeZone,
        ),
        sunset: WeatherTimeZone.parseLocal(sunsets[index] as String, timeZone),
      ),
      growable: false,
    );
  }
}
