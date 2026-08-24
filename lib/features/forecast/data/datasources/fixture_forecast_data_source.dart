import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../../core/time/weather_clock.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/services/rain_rate_scale.dart';
import '../../domain/services/weather_brief_builder.dart';

enum ReferenceWeatherScenario { dry, light, moderate, heavy, multipleEpisodes }

extension ReferenceWeatherScenarioFixture on ReferenceWeatherScenario {
  String get fixtureName => switch (this) {
    ReferenceWeatherScenario.dry => 'dry',
    ReferenceWeatherScenario.light => 'light_rain_reference',
    ReferenceWeatherScenario.moderate => 'moderate_rain',
    ReferenceWeatherScenario.heavy => 'heavy_rain',
    ReferenceWeatherScenario.multipleEpisodes => 'multiple_showers',
  };
}

final class FixtureForecastDataSource {
  const FixtureForecastDataSource({
    this.fixtureName = 'light_rain',
    this.clock = const SystemWeatherClock(),
    this.timeZone = 'Europe/Paris',
    this.locationName,
    this.providerName = 'Fixture Open-Meteo',
  });

  final String fixtureName;
  final WeatherClock clock;
  final String timeZone;
  final String? locationName;
  final String providerName;

  Future<Forecast> load() async {
    final source = await rootBundle.loadString(
      'assets/fixtures/$fixtureName.json',
    );
    final json = jsonDecode(source) as Map<String, dynamic>;
    final value = clock.nowUtc;
    final anchor = DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
    final localAnchor = WeatherTimeZone.wallTime(anchor, timeZone);
    final pointsJson = json['points'] as List<dynamic>;
    final points = pointsJson
        .map((raw) {
          final pair = raw as List<dynamic>;
          final rate = (pair[1] as num).toDouble();
          return RainPoint(
            time: anchor.add(Duration(minutes: (pair[0] as num).toInt())),
            rateMmPerHour: rate,
            probability: rate == 0 ? 0 : (0.35 + rate / 15).clamp(0, 1),
            intensity: RainRateScale.intensityFor(rate),
          );
        })
        .toList(growable: false);

    final summary = WeatherBriefBuilder.build(now: anchor, points: points);
    final hourly = List.generate(24, (index) {
      final rainPoint = points[index.clamp(0, points.length - 1)];
      return HourlyForecast(
        time: anchor.add(Duration(hours: index)),
        temperatureCelsius:
            (json['temperature_c'] as num).toDouble() - index * 0.18,
        weatherCode: rainPoint.rateMmPerHour > 0.5
            ? 61
            : rainPoint.rateMmPerHour > 0
            ? 51
            : index > 8
            ? 2
            : 1,
        precipitationProbability: rainPoint.rateMmPerHour == 0 ? 8 : 70,
        precipitationMm: rainPoint.rateMmPerHour,
        windKph: (json['wind_kph'] as num).toDouble(),
      );
    }, growable: false);
    final daily = List.generate(
      10,
      (index) => DailyForecast(
        date: DateTime(
          localAnchor.year,
          localAnchor.month,
          localAnchor.day + index,
        ),
        weatherCode: index == 2 || index == 3
            ? 61
            : index.isEven
            ? 2
            : 1,
        temperatureMax: 24 - index * 0.25,
        temperatureMin: 16 - index * 0.15,
        precipitationProbability: index == 2
            ? 75
            : index == 3
            ? 50
            : 15,
        sunrise: WeatherTimeZone.instantFromLocal(
          DateTime(
            localAnchor.year,
            localAnchor.month,
            localAnchor.day + index,
            6,
            42,
          ),
          timeZone,
        ),
        sunset: WeatherTimeZone.instantFromLocal(
          DateTime(
            localAnchor.year,
            localAnchor.month,
            localAnchor.day + index,
            21,
            4,
          ),
          timeZone,
        ),
      ),
      growable: false,
    );

    return Forecast(
      locationName: locationName ?? json['location'] as String,
      updatedAt: anchor,
      temperatureCelsius: (json['temperature_c'] as num).toDouble(),
      windKph: (json['wind_kph'] as num).toDouble(),
      utcOffsetSeconds: WeatherTimeZone.atLocation(
        anchor,
        timeZone,
      ).timeZoneOffset.inSeconds,
      timeZone: timeZone,
      providerName: providerName,
      currentWeatherCode: points.first.rateMmPerHour > 0 ? 61 : 1,
      brief: summary.brief,
      points: points,
      windows: summary.windows,
      hourly: hourly,
      daily: daily,
    );
  }
}
