import '../../../../core/location/coordinates.dart';
import '../entities/radar_frame.dart';

final class CachedRadarFrames {
  const CachedRadarFrames({required this.frames, required this.cachedAt});

  final List<RadarFrame> frames;
  final DateTime cachedAt;

  bool isStaleAt(DateTime nowUtc) =>
      nowUtc.toUtc().difference(cachedAt.toUtc()) > const Duration(minutes: 15);
}

abstract interface class RadarRepository {
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates);

  Future<List<RadarFrame>> getFrames(Coordinates coordinates);
}
