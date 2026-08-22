import '../entities/radar_frame.dart';

/// Bounds metadata and tile work per radar refresh without hiding the most
/// recent observed rain or the beginning of the nowcast.
abstract final class RadarFramePolicy {
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
        ),
        growable: false,
      );
}
