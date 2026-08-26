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
  // Drops-like playback: each ten-minute weather step remains visible long
  // enough to follow the same rain cell across the map. The playhead still
  // moves at display refresh rate between timestamps, so a twelve-frame
  // future sequence takes about 24 seconds instead of racing through in five.
  static const playbackFrameDuration = Duration(milliseconds: 2000);
  static const tileCrossFadeDuration = Duration(milliseconds: 90);

  // Alpha blending two precipitation fields makes cells look as though they
  // are evaporating. LibreWXR provides optical-flow-interpolated ten-minute
  // frames, so an atomic, preloaded swap is both smoother and more truthful.
  static const opacityCrossFadeEnabled = false;
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

  /// Smooth display time between two real source timestamps. This animates
  /// only the cursor; tile content still changes exclusively on a provider
  /// frame, so no precipitation field is fabricated on the phone.
  static DateTime interpolateFrameTime(
    DateTime current,
    DateTime next,
    double progress,
  ) {
    final elapsedMicroseconds = next.difference(current).inMicroseconds;
    if (elapsedMicroseconds <= 0) return current;
    return current.add(
      Duration(
        microseconds: (elapsedMicroseconds * progress.clamp(0.0, 1.0)).round(),
      ),
    );
  }

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
      // A sleeping app or a transient provider failure can leave the last
      // usable radar product behind the current clock. Collapsing the window
      // to `end -> end` pins every playback timestamp to x=0 even while the
      // frames themselves continue advancing. In that degraded state, show
      // the real available playback interval until the background refresh
      // replaces it with fresh frames.
      if (!now.isBefore(end)) {
        final observations =
            frames.where((frame) => frame.isObservation).toList()
              ..sort((left, right) => left.time.compareTo(right.time));
        final availableStart = observations.isNotEmpty
            ? observations.last.time
            : nowcasts.first.time;
        return RadarTimelineWindow(
          start: availableStart.isBefore(end) ? availableStart : end,
          end: end,
        );
      }
      return RadarTimelineWindow(start: now, end: end);
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
