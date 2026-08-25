import '../entities/radar_frame.dart';
import '../../../../core/weather/weather_data_provenance.dart';

final class RadarTimelineWindow {
  const RadarTimelineWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Bounds metadata and tile work per radar refresh without hiding the most
/// recent observed rain or the beginning of the nowcast.
abstract final class RadarFramePolicy {
  static const nowcastHorizon = Duration(minutes: 60);
  static const maxFrames = 24;
  static const maxObservedFrames = 12;
  static const maxNowcastFrames = 12;

  static List<T> select<T>(List<T> observed, List<T> nowcast) {
    final observedStart = observed.length > maxObservedFrames
        ? observed.length - maxObservedFrames
        : 0;
    return [...observed.skip(observedStart), ...nowcast.take(maxNowcastFrames)];
  }

  static List<RadarFrame> normalizeProgress(List<RadarFrame> frames) =>
      List.generate(
        frames.length,
        (index) => RadarFrame(
          time: frames[index].time,
          progress: frames.length == 1 ? 1 : index / (frames.length - 1),
          tileUrlTemplate: frames[index].tileUrlTemplate,
          kind: frames[index].kind,
          providerName: frames[index].providerName,
          pointRainRateMmPerHour: frames[index].pointRainRateMmPerHour,
          pointRainSource: frames[index].pointRainSource,
        ),
        growable: false,
      );

  static WeatherDataKind futureKind({
    required DateTime latestObservation,
    required DateTime forecastTime,
  }) => forecastTime.difference(latestObservation) > nowcastHorizon
      ? WeatherDataKind.modelForecast
      : WeatherDataKind.radarNowcast;

  /// Uses only timestamps backed by an available image. The first future hour
  /// is radar nowcast; an optional second hour is explicitly model forecast.
  static RadarTimelineWindow timelineWindow(
    List<RadarFrame> frames,
    DateTime now,
  ) {
    if (frames.isEmpty) return RadarTimelineWindow(start: now, end: now);
    final nowcasts = frames.where((frame) => frame.isForecast).toList()
      ..sort((left, right) => left.time.compareTo(right.time));
    if (nowcasts.isNotEmpty) {
      final end = nowcasts.last.time;
      return RadarTimelineWindow(
        start: now.isBefore(end) ? now : end,
        end: end,
      );
    }

    final observations = frames.where((frame) => frame.isObservation).toList()
      ..sort((left, right) => left.time.compareTo(right.time));
    final available = observations.isEmpty ? frames : observations;
    return RadarTimelineWindow(
      start: available.first.time,
      end: available.last.time,
    );
  }
}
