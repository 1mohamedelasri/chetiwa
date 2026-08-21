import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/location/coordinates.dart';
import '../../../../core/storage/bounded_preference_cache.dart';
import '../../../../core/time/weather_clock.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/repositories/forecast_repository.dart';

final class ForecastCacheDataSource {
  const ForecastCacheDataSource({this.clock = const SystemWeatherClock()});

  final WeatherClock clock;

  Future<CachedForecast?> read(Coordinates coordinates) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(coordinates));
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      await BoundedPreferenceCache.touch(
        preferences,
        namespace: 'forecast:v2',
        key: _key(coordinates),
        maxEntries: 8,
      );
      return CachedForecast(
        forecast: _forecastFromJson(json['forecast'] as Map<String, dynamic>),
        cachedAt: DateTime.parse(json['cached_at'] as String),
      );
    } on Object {
      await BoundedPreferenceCache.forget(
        preferences,
        namespace: 'forecast:v2',
        key: _key(coordinates),
      );
      return null;
    }
  }

  Future<void> write(Coordinates coordinates, Forecast forecast) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(coordinates),
      jsonEncode({
        'cached_at': clock.nowUtc.toIso8601String(),
        'forecast': _forecastToJson(forecast),
      }),
    );
    await BoundedPreferenceCache.touch(
      preferences,
      namespace: 'forecast:v2',
      key: _key(coordinates),
      maxEntries: 8,
    );
  }

  String _key(Coordinates coordinates) =>
      'forecast:v2:${coordinates.latitude.toStringAsFixed(3)}:${coordinates.longitude.toStringAsFixed(3)}';

  Map<String, dynamic> _forecastToJson(Forecast forecast) => {
    'location': forecast.locationName,
    'updated_at': forecast.updatedAt.toIso8601String(),
    'temperature_c': forecast.temperatureCelsius,
    'wind_kph': forecast.windKph,
    'weather_code': forecast.currentWeatherCode,
    'utc_offset_seconds': forecast.utcOffsetSeconds,
    'time_zone': forecast.timeZone,
    'provider_name': forecast.providerName,
    'brief': {
      'type': forecast.brief.type.name,
      'intensity': forecast.brief.intensity.name,
      'headline': forecast.brief.headline,
      'detail': forecast.brief.detail,
      'rain_start': forecast.brief.rainStart?.toIso8601String(),
      'rain_end': forecast.brief.rainEnd?.toIso8601String(),
    },
    'points': forecast.points
        .map(
          (point) => {
            'time': point.time.toIso8601String(),
            'rate': point.rateMmPerHour,
            'probability': point.probability,
            'intensity': point.intensity.name,
          },
        )
        .toList(growable: false),
    'windows': forecast.windows
        .map(
          (window) => {
            'start': window.start.toIso8601String(),
            'end': window.end?.toIso8601String(),
            'intensity': window.intensity.name,
          },
        )
        .toList(growable: false),
    'hourly': forecast.hourly
        .map(
          (item) => {
            'time': item.time.toIso8601String(),
            'temperature_c': item.temperatureCelsius,
            'weather_code': item.weatherCode,
            'precipitation_probability': item.precipitationProbability,
            'precipitation_mm': item.precipitationMm,
            'wind_kph': item.windKph,
          },
        )
        .toList(growable: false),
    'daily': forecast.daily
        .map(
          (item) => {
            'date': item.date.toIso8601String(),
            'weather_code': item.weatherCode,
            'temperature_max': item.temperatureMax,
            'temperature_min': item.temperatureMin,
            'precipitation_probability': item.precipitationProbability,
            'sunrise': item.sunrise.toIso8601String(),
            'sunset': item.sunset.toIso8601String(),
          },
        )
        .toList(growable: false),
  };

  Forecast _forecastFromJson(Map<String, dynamic> json) {
    final brief = json['brief'] as Map<String, dynamic>;
    return Forecast(
      locationName: json['location'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      temperatureCelsius: (json['temperature_c'] as num).toDouble(),
      windKph: (json['wind_kph'] as num).toDouble(),
      currentWeatherCode: (json['weather_code'] as num?)?.toInt() ?? 0,
      utcOffsetSeconds: (json['utc_offset_seconds'] as num?)?.toInt() ?? 0,
      timeZone: json['time_zone'] as String? ?? 'Etc/UTC',
      providerName: json['provider_name'] as String? ?? 'Open-Meteo',
      brief: WeatherBrief(
        type: WeatherBriefType.values.byName(brief['type'] as String),
        intensity: RainIntensity.values.byName(brief['intensity'] as String),
        headline: brief['headline'] as String,
        detail: brief['detail'] as String,
        rainStart: _dateOrNull(brief['rain_start']),
        rainEnd: _dateOrNull(brief['rain_end']),
      ),
      points: (json['points'] as List<dynamic>)
          .map((raw) {
            final point = raw as Map<String, dynamic>;
            return RainPoint(
              time: DateTime.parse(point['time'] as String),
              rateMmPerHour: (point['rate'] as num).toDouble(),
              probability: (point['probability'] as num?)?.toDouble(),
              intensity: RainIntensity.values.byName(
                point['intensity'] as String,
              ),
            );
          })
          .toList(growable: false),
      windows: (json['windows'] as List<dynamic>)
          .map((raw) {
            final window = raw as Map<String, dynamic>;
            return RainWindow(
              start: DateTime.parse(window['start'] as String),
              end: _dateOrNull(window['end']),
              intensity: RainIntensity.values.byName(
                window['intensity'] as String,
              ),
            );
          })
          .toList(growable: false),
      hourly: (json['hourly'] as List<dynamic>? ?? const [])
          .map((raw) {
            final item = raw as Map<String, dynamic>;
            return HourlyForecast(
              time: DateTime.parse(item['time'] as String),
              temperatureCelsius: (item['temperature_c'] as num).toDouble(),
              weatherCode: (item['weather_code'] as num).toInt(),
              precipitationProbability:
                  (item['precipitation_probability'] as num).toInt(),
              precipitationMm: (item['precipitation_mm'] as num).toDouble(),
              windKph: (item['wind_kph'] as num).toDouble(),
            );
          })
          .toList(growable: false),
      daily: (json['daily'] as List<dynamic>? ?? const [])
          .map((raw) {
            final item = raw as Map<String, dynamic>;
            return DailyForecast(
              date: DateTime.parse(item['date'] as String),
              weatherCode: (item['weather_code'] as num).toInt(),
              temperatureMax: (item['temperature_max'] as num).toDouble(),
              temperatureMin: (item['temperature_min'] as num).toDouble(),
              precipitationProbability:
                  (item['precipitation_probability'] as num).toInt(),
              sunrise: DateTime.parse(item['sunrise'] as String),
              sunset: DateTime.parse(item['sunset'] as String),
            );
          })
          .toList(growable: false),
    );
  }

  DateTime? _dateOrNull(Object? value) =>
      value is String ? DateTime.parse(value) : null;
}
