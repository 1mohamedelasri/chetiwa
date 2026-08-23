import '../../../radar/domain/entities/radar_frame.dart';
import '../entities/forecast.dart';
import 'rain_rate_scale.dart';

/// Replaces model values only inside LibreWXR's sampled nowcast window.
///
/// Both Graph and Radar consume this function so they always display the same
/// rain episodes for the selected point.
Forecast alignForecastWithRadarNowcast(
  Forecast forecast,
  List<RadarFrame> radarFrames,
  DateTime nowUtc,
) {
  final samples =
      radarFrames
          .where(
            (frame) =>
                frame.isNowcast &&
                frame.pointRainRateMmPerHour != null &&
                frame.time.isAfter(nowUtc),
          )
          .map(
            (frame) => RainPoint(
              time: frame.time,
              rateMmPerHour: frame.pointRainRateMmPerHour!,
              probability:
                  frame.pointRainRateMmPerHour! >= RainRateScale.traceThreshold
                  ? 1
                  : 0,
              intensity: RainRateScale.intensityFor(
                frame.pointRainRateMmPerHour!,
              ),
            ),
          )
          .toList(growable: false)
        ..sort((left, right) => left.time.compareTo(right.time));
  if (samples.isEmpty) return forecast;

  final radarStart = samples.first.time;
  final radarEnd = samples.last.time;
  final merged = <RainPoint>[
    ...forecast.points.where(
      (point) =>
          point.time.isBefore(radarStart) || point.time.isAfter(radarEnd),
    ),
    ...samples,
  ]..sort((left, right) => left.time.compareTo(right.time));
  final modelLabel = forecast.providerName.contains('AROME')
      ? 'AROME'
      : forecast.providerName.contains('Open-Meteo')
      ? 'Open-Meteo'
      : forecast.providerName;
  return forecast.copyWith(
    points: merged,
    providerName: 'LibreWXR nowcast + $modelLabel',
  );
}
