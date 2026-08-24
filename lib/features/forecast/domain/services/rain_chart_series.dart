import '../entities/forecast.dart';
import 'rain_rate_scale.dart';

/// Builds a continuous chart series covering the complete requested horizon.
///
/// Forecast providers do not always publish a sample exactly on the 2 h / 24 h
/// boundary. Interpolating that boundary prevents the rendered line from
/// stopping at the last provider timestamp before the right edge.
List<RainPoint> buildRainChartSeries({
  required List<RainPoint> points,
  required RainPoint currentRain,
  required DateTime now,
  required Duration duration,
}) {
  final end = now.add(duration);
  final ordered = [...points]
    ..sort((left, right) => left.time.compareTo(right.time));
  final series = <RainPoint>[_atTime(currentRain, now)];

  series.addAll(
    ordered.where(
      (point) => point.time.isAfter(now) && point.time.isBefore(end),
    ),
  );

  final exactEnd = ordered.where((point) => point.time == end).firstOrNull;
  series.add(exactEnd ?? _interpolateEnd(ordered, series.last, end));

  // A provider refresh can briefly return duplicate timestamps. Keep the last
  // value for each instant so the painter never doubles back on the x-axis.
  final unique = <DateTime, RainPoint>{};
  for (final point in series) {
    unique[point.time] = point;
  }
  return unique.values.toList(growable: false)
    ..sort((left, right) => left.time.compareTo(right.time));
}

RainPoint _interpolateEnd(
  List<RainPoint> ordered,
  RainPoint fallback,
  DateTime end,
) {
  RainPoint left = fallback;
  RainPoint? right;
  for (final point in ordered) {
    if (!point.time.isAfter(end)) {
      if (point.time.isAfter(left.time)) left = point;
      continue;
    }
    right = point;
    break;
  }
  if (right == null || !left.time.isBefore(end)) return _atTime(left, end);

  final span = right.time.difference(left.time).inMilliseconds;
  final elapsed = end.difference(left.time).inMilliseconds;
  final ratio = span == 0 ? 0.0 : (elapsed / span).clamp(0.0, 1.0);
  final rate =
      left.rateMmPerHour + (right.rateMmPerHour - left.rateMmPerHour) * ratio;
  final probability = switch ((left.probability, right.probability)) {
    (final double leftValue, final double rightValue) =>
      leftValue + (rightValue - leftValue) * ratio,
    _ => left.probability ?? right.probability,
  };
  return RainPoint(
    time: end,
    rateMmPerHour: rate,
    probability: probability,
    intensity: RainRateScale.intensityFor(rate),
  );
}

RainPoint _atTime(RainPoint source, DateTime time) => RainPoint(
  time: time,
  rateMmPerHour: source.rateMmPerHour,
  probability: source.probability,
  intensity: source.intensity,
);
