import '../entities/forecast.dart';
import 'rain_rate_scale.dart';

typedef ForecastSummary = ({WeatherBrief brief, List<RainWindow> windows});

abstract final class WeatherBriefBuilder {
  static ForecastSummary build({
    required DateTime now,
    required List<RainPoint> points,
    String Function(DateTime)? formatTime,
  }) {
    final windows = _buildWindows(points);
    final decisionLimit = now.add(const Duration(hours: 2));
    final upcoming = windows
        .where((window) => window.start.isBefore(decisionLimit))
        .toList(growable: false);

    if (upcoming.isEmpty) {
      return (
        brief: const WeatherBrief(
          type: WeatherBriefType.dry,
          intensity: RainIntensity.none,
          headline: 'Pas de pluie dans les 2 h',
          detail: 'Conditions sèches pour sortir',
        ),
        windows: windows,
      );
    }

    final first = upcoming.first;
    final duration = first.end?.difference(first.start).inMinutes;
    final intensity = _intensityLabel(first.intensity);
    final isRaining = !first.start.isAfter(now.add(const Duration(minutes: 1)));

    if (isRaining) {
      return (
        brief: WeatherBrief(
          type: WeatherBriefType.raining,
          intensity: first.intensity,
          headline: 'Pluie en cours',
          detail: first.end == null
              ? '$intensity · durée incertaine'
              : '$intensity · fin vers ${(formatTime ?? _time)(first.end!)}',
          rainStart: first.start,
          rainEnd: first.end,
        ),
        windows: windows,
      );
    }

    if (upcoming.length > 1) {
      final minutes = first.start.difference(now).inMinutes.clamp(1, 120);
      return (
        brief: WeatherBrief(
          type: WeatherBriefType.multipleEpisodes,
          intensity: first.intensity,
          headline: 'Première averse dans $minutes min',
          detail: 'Deux épisodes possibles dans les 2 h',
          rainStart: first.start,
          rainEnd: first.end,
        ),
        windows: windows,
      );
    }

    final minutes = first.start.difference(now).inMinutes.clamp(1, 120);
    return (
      brief: WeatherBrief(
        type: WeatherBriefType.imminent,
        intensity: first.intensity,
        headline: 'Pluie dans $minutes min',
        detail: duration == null
            ? intensity
            : '$intensity · environ $duration min',
        rainStart: first.start,
        rainEnd: first.end,
      ),
      windows: windows,
    );
  }

  static List<RainWindow> _buildWindows(List<RainPoint> points) {
    final windows = <RainWindow>[];
    DateTime? start;
    RainIntensity strongest = RainIntensity.none;

    for (final point in points) {
      final raining = RainRateScale.isRain(point.rateMmPerHour);
      if (raining) {
        start ??= point.time;
        final intensity = RainRateScale.intensityFor(point.rateMmPerHour);
        if (intensity.index > strongest.index) {
          strongest = intensity;
        }
      } else if (start != null) {
        windows.add(
          RainWindow(start: start, end: point.time, intensity: strongest),
        );
        start = null;
        strongest = RainIntensity.none;
      }
    }
    if (start != null) {
      windows.add(RainWindow(start: start, intensity: strongest));
    }
    return List.unmodifiable(windows);
  }

  static String _intensityLabel(RainIntensity intensity) => switch (intensity) {
    RainIntensity.none => 'Très faible',
    RainIntensity.light => 'Faible',
    RainIntensity.moderate => 'Modérée',
    RainIntensity.heavy => 'Forte',
  };

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
