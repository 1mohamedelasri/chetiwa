import 'package:equatable/equatable.dart';

import '../../../../core/time/weather_clock.dart';
import '../../../../core/weather/weather_data_provenance.dart';
import '../entities/forecast.dart';
import 'weather_brief_builder.dart';

/// A coherent view of every weather surface at one absolute instant.
final class ForecastSnapshot extends Equatable {
  const ForecastSnapshot({
    required this.nowUtc,
    required this.wallClock,
    required this.brief,
    required this.windows,
    required this.currentRain,
    required this.hourly,
    required this.daily,
    required this.currentProvenance,
    required this.forecastProvenance,
  });

  final DateTime nowUtc;
  final DateTime wallClock;
  final WeatherBrief brief;
  final List<RainWindow> windows;
  final RainPoint currentRain;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;
  final WeatherDataProvenance currentProvenance;
  final WeatherDataProvenance forecastProvenance;

  @override
  List<Object> get props => [
    nowUtc,
    wallClock,
    brief,
    windows,
    currentRain,
    hourly,
    daily,
    currentProvenance,
    forecastProvenance,
  ];
}

abstract final class ForecastSnapshotBuilder {
  static ForecastSnapshot build({
    required Forecast forecast,
    required DateTime nowUtc,
  }) {
    final now = nowUtc.toUtc();
    final currentRain =
        forecast.rainPointAt(now) ??
        RainPoint(
          time: now,
          rateMmPerHour: 0,
          probability: 0,
          intensity: RainIntensity.none,
        );
    final decisionPoints = <RainPoint>[
      currentRain,
      ...forecast.points.where((point) => point.time.isAfter(now)),
    ];
    final summary = WeatherBriefBuilder.build(
      now: now,
      points: decisionPoints,
      formatTime: (instant) =>
          WeatherTimeZone.hourMinute(instant, forecast.timeZone),
    );
    final currentHour = WeatherTimeZone.startOfLocalHour(
      now,
      forecast.timeZone,
    );
    final localNow = WeatherTimeZone.wallTime(now, forecast.timeZone);
    final hourly = forecast.hourly
        .where((item) => !item.time.isBefore(currentHour))
        .toList(growable: false);
    final daily = forecast.daily
        .where((item) {
          final date = item.date;
          return DateTime(date.year, date.month, date.day).compareTo(
                DateTime(localNow.year, localNow.month, localNow.day),
              ) >=
              0;
        })
        .toList(growable: false);
    return ForecastSnapshot(
      nowUtc: now,
      wallClock: localNow,
      brief: summary.brief,
      windows: summary.windows,
      currentRain: currentRain,
      hourly: hourly,
      daily: daily,
      currentProvenance: WeatherDataProvenance(
        kind: WeatherDataKind.modelEstimate,
        provider: forecast.providerName,
        validAt: now,
      ),
      forecastProvenance: WeatherDataProvenance(
        kind: WeatherDataKind.modelForecast,
        provider: forecast.providerName,
        validAt: now,
      ),
    );
  }
}
