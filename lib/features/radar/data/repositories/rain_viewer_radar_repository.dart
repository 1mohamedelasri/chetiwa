import '../../../../core/location/coordinates.dart';
import '../../../../core/weather/weather_data_provenance.dart';
import '../../../../core/weather/weather_data_health.dart';
import '../../domain/entities/radar_frame.dart';
import '../../domain/repositories/radar_repository.dart';
import '../../domain/services/radar_frame_policy.dart';
import '../cache/radar_cache_data_source.dart';
import '../providers/rain_viewer_radar_provider.dart';

final class RainViewerRadarRepository implements RadarRepository {
  const RainViewerRadarRepository({
    required RainViewerRadarProvider provider,
    required RadarCacheDataSource cache,
  }) : _provider = provider,
       _cache = cache;

  final RainViewerRadarProvider _provider;
  final RadarCacheDataSource _cache;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) =>
      _cache.read(coordinates);

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    final response = await _provider.fetchMetadata();
    final host = response['host'];
    final radar = response['radar'];
    if (host is! String || radar is! Map<String, dynamic>) {
      throw const WeatherDataException(
        WeatherDataIssue.invalidResponse,
        'Métadonnées radar incomplètes',
      );
    }
    final past = radar['past'] as List<dynamic>? ?? const [];
    // RainViewer retired future/nowcast frames on 1 January 2026. Never
    // surface a stale or legacy `nowcast` field as a forecast to the user.
    // A licensed production provider can still return true nowcast frames via
    // ChetiwaRadarRepository, which keeps the domain support intact.
    final rawFrames = RadarFramePolicy.select(
      past
          .whereType<Map<String, dynamic>>()
          .map((frame) => (json: frame, forecast: false))
          .toList(growable: false),
      const [],
    );
    if (rawFrames.isEmpty) {
      throw const WeatherDataException(
        WeatherDataIssue.noRadarCoverage,
        'Aucune image radar disponible pour cette zone',
      );
    }

    final frames = RadarFramePolicy.normalizeProgress(
      List.generate(rawFrames.length, (index) {
        final raw = rawFrames[index];
        final path = raw.json['path'];
        final timestamp = raw.json['time'];
        if (path is! String || timestamp is! num || path.isEmpty) {
          throw const WeatherDataException(
            WeatherDataIssue.invalidResponse,
            'Image radar invalide',
          );
        }
        return RadarFrame(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() * 1000,
            isUtc: true,
          ),
          progress: 0,
          // RainViewer's first option enables server-side smoothing. It keeps
          // genuine precipitation cells legible without manufacturing echoes.
          tileUrlTemplate: '$host$path/256/{z}/{x}/{y}/2/1_0.png',
          kind: raw.forecast
              ? WeatherDataKind.radarNowcast
              : WeatherDataKind.radarObservation,
        );
      }, growable: false),
    );
    await _cache.write(coordinates, frames);
    return frames;
  }
}
