import 'package:equatable/equatable.dart';

import '../../../../core/time/weather_clock.dart';
import '../services/rain_rate_scale.dart';
import 'rain_intensity.dart';

export 'rain_intensity.dart';

enum WeatherBriefType { dry, imminent, raining, multipleEpisodes }

final class RainPoint extends Equatable {
  const RainPoint({
    required this.time,
    required this.rateMmPerHour,
    required this.intensity,
    this.probability,
  });

  final DateTime time;
  final double rateMmPerHour;
  final double? probability;
  final RainIntensity intensity;

  @override
  List<Object?> get props => [time, rateMmPerHour, probability, intensity];
}

final class RainWindow extends Equatable {
  const RainWindow({required this.start, required this.intensity, this.end});

  final DateTime start;
  final DateTime? end;
  final RainIntensity intensity;

  @override
  List<Object?> get props => [start, end, intensity];
}

final class WeatherBrief extends Equatable {
  const WeatherBrief({
    required this.type,
    required this.intensity,
    required this.headline,
    required this.detail,
    this.rainStart,
    this.rainEnd,
  });

  final WeatherBriefType type;
  final DateTime? rainStart;
  final DateTime? rainEnd;
  final RainIntensity intensity;
  final String headline;
  final String detail;

  @override
  List<Object?> get props => [
    type,
    rainStart,
    rainEnd,
    intensity,
    headline,
    detail,
  ];
}

final class Forecast extends Equatable {
  const Forecast({
    required this.locationName,
    required this.updatedAt,
    required this.temperatureCelsius,
    required this.windKph,
    required this.brief,
    required this.points,
    required this.windows,
    this.currentWeatherCode = 0,
    this.utcOffsetSeconds = 0,
    this.timeZone = 'Etc/UTC',
    this.providerName = 'Open-Meteo',
    this.hourly = const [],
    this.daily = const [],
  });

  final String locationName;
  final DateTime updatedAt;
  final double temperatureCelsius;
  final double windKph;
  final WeatherBrief brief;
  final List<RainPoint> points;
  final List<RainWindow> windows;
  final int currentWeatherCode;

  /// Offset of the selected place from UTC, supplied by the forecast API.
  /// Kept for diagnostics and cache migration; conversion uses [timeZone].
  final int utcOffsetSeconds;
  final String timeZone;
  final String providerName;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;

  /// Converts an absolute instant to the selected place's wall clock.
  DateTime wallClockForInstant(DateTime instant) =>
      WeatherTimeZone.wallTime(instant, timeZone);

  RainPoint? rainPointAt(DateTime time) {
    if (points.isEmpty) return null;
    final ordered = [...points]..sort((a, b) => a.time.compareTo(b.time));
    RainPoint? before;
    RainPoint? after;
    for (final point in ordered) {
      if (point.time == time) return point;
      if (point.time.isBefore(time)) {
        before = point;
      } else {
        after = point;
        break;
      }
    }
    final left = before;
    final right = after;
    if (left == null) {
      return RainPoint(
        time: time,
        rateMmPerHour: right!.rateMmPerHour,
        probability: right.probability,
        intensity: right.intensity,
      );
    }
    if (right == null) return null;
    final span = right.time.difference(left.time).inMilliseconds;
    final elapsed = time.difference(left.time).inMilliseconds;
    final ratio = span == 0 ? 0.0 : (elapsed / span).clamp(0.0, 1.0);
    final rate =
        left.rateMmPerHour + (right.rateMmPerHour - left.rateMmPerHour) * ratio;
    final probability = switch ((left.probability, right.probability)) {
      (final double leftValue, final double rightValue) =>
        leftValue + (rightValue - leftValue) * ratio,
      _ => left.probability ?? right.probability,
    };
    return RainPoint(
      time: time,
      rateMmPerHour: rate,
      probability: probability,
      intensity: RainRateScale.intensityFor(rate),
    );
  }

  Forecast copyWith({
    String? locationName,
    List<RainPoint>? points,
    String? providerName,
  }) => Forecast(
    locationName: locationName ?? this.locationName,
    updatedAt: updatedAt,
    temperatureCelsius: temperatureCelsius,
    windKph: windKph,
    brief: brief,
    points: points ?? this.points,
    windows: windows,
    currentWeatherCode: currentWeatherCode,
    utcOffsetSeconds: utcOffsetSeconds,
    timeZone: timeZone,
    providerName: providerName ?? this.providerName,
    hourly: hourly,
    daily: daily,
  );

  @override
  List<Object> get props => [
    locationName,
    updatedAt,
    temperatureCelsius,
    windKph,
    brief,
    points,
    windows,
    currentWeatherCode,
    utcOffsetSeconds,
    timeZone,
    providerName,
    hourly,
    daily,
  ];
}

final class HourlyForecast extends Equatable {
  const HourlyForecast({
    required this.time,
    required this.temperatureCelsius,
    required this.weatherCode,
    required this.precipitationProbability,
    required this.precipitationMm,
    required this.windKph,
  });

  final DateTime time;
  final double temperatureCelsius;
  final int weatherCode;
  final int precipitationProbability;
  final double precipitationMm;
  final double windKph;

  @override
  List<Object> get props => [
    time,
    temperatureCelsius,
    weatherCode,
    precipitationProbability,
    precipitationMm,
    windKph,
  ];
}

final class DailyForecast extends Equatable {
  const DailyForecast({
    required this.date,
    required this.weatherCode,
    required this.temperatureMax,
    required this.temperatureMin,
    required this.precipitationProbability,
    required this.sunrise,
    required this.sunset,
  });

  final DateTime date;
  final int weatherCode;
  final double temperatureMax;
  final double temperatureMin;
  final int precipitationProbability;
  final DateTime sunrise;
  final DateTime sunset;

  @override
  List<Object> get props => [
    date,
    weatherCode,
    temperatureMax,
    temperatureMin,
    precipitationProbability,
    sunrise,
    sunset,
  ];
}
