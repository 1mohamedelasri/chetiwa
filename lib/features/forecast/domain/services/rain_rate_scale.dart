import '../entities/rain_intensity.dart';

/// One shared rain scale for domain decisions and every chart surface.
///
/// Keeping fixed thresholds prevents a weak shower from filling a chart simply
/// because it is the largest value in the current time window.
abstract final class RainRateScale {
  static const traceThreshold = 0.05;
  static const lightUpperBound = 0.5;
  static const moderateUpperBound = 4.0;
  static const visualHeavyCap = 12.0;

  static bool isRain(double rateMmPerHour) => rateMmPerHour >= traceThreshold;

  static RainIntensity intensityFor(double rateMmPerHour) =>
      switch (rateMmPerHour) {
        < traceThreshold => RainIntensity.none,
        < lightUpperBound => RainIntensity.light,
        < moderateUpperBound => RainIntensity.moderate,
        _ => RainIntensity.heavy,
      };

  /// Maps a rate to the fixed visual bands used by Graph and Radar:
  /// light 0–24%, moderate 24–56%, heavy 56–100%.
  static double normalized(double rateMmPerHour) {
    final rate = rateMmPerHour.clamp(0, visualHeavyCap).toDouble();
    if (rate < lightUpperBound) {
      return rate / lightUpperBound * 0.24;
    }
    if (rate < moderateUpperBound) {
      return 0.24 +
          (rate - lightUpperBound) /
              (moderateUpperBound - lightUpperBound) *
              0.32;
    }
    return 0.56 +
        (rate - moderateUpperBound) /
            (visualHeavyCap - moderateUpperBound) *
            0.44;
  }

  /// Consecutive rainy samples as independent closed episodes.
  ///
  /// Renderers use these ranges instead of joining every sample, so dry
  /// periods never become a misleading continuous precipitation line.
  static List<({int first, int last})> episodeRanges(Iterable<double> rates) {
    final values = rates.toList(growable: false);
    final episodes = <({int first, int last})>[];
    var index = 0;
    while (index < values.length) {
      if (!isRain(values[index])) {
        index++;
        continue;
      }
      final first = index;
      while (index + 1 < values.length && isRain(values[index + 1])) {
        index++;
      }
      episodes.add((first: first, last: index));
      index++;
    }
    return episodes;
  }
}
