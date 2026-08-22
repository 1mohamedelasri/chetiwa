import '../entities/radar_frame.dart';

enum RadarSubscription { free, premium }

final class RadarUsagePolicy {
  const RadarUsagePolicy({
    required this.subscription,
    required this.maxFrames,
    required this.maxZoom,
    required this.monthlySessions,
  });

  const RadarUsagePolicy.free()
    : this(
        subscription: RadarSubscription.free,
        maxFrames: 12,
        maxZoom: 10,
        monthlySessions: 20,
      );

  const RadarUsagePolicy.premium()
    : this(
        subscription: RadarSubscription.premium,
        maxFrames: 24,
        maxZoom: 12,
        monthlySessions: 200,
      );

  final RadarSubscription subscription;
  final int maxFrames;
  final double maxZoom;
  final int monthlySessions;

  static const freeDefault = RadarUsagePolicy.free();
  static const premiumDefault = RadarUsagePolicy.premium();

  List<T> selectFrameIndexes<T>(List<T> frames) {
    if (frames.length <= maxFrames) return List<T>.of(frames);
    return frames.sublist(frames.length - maxFrames);
  }

  List<RadarFrame> limitFrames(List<RadarFrame> frames) =>
      selectFrameIndexes(frames);
}
