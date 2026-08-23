import '../../../../core/location/coordinates.dart';
import '../../../../core/config/api_config.dart';
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
    final usesLibreWxr = ApiConfig.radarMetadataUrl.contains(
      'radar.ezplatforms.com',
    );
    final pointNowcastFuture = usesLibreWxr
        ? _provider.fetchPointNowcast(coordinates)
        : Future<List<Map<String, dynamic>>>.value(const []);
    final response = await _provider.fetchMetadata();
    final pointNowcast = await pointNowcastFuture;
    final pointByTimestamp = <int, Map<String, dynamic>>{
      for (final point in pointNowcast)
        if (point['time'] is num) (point['time'] as num).toInt(): point,
    };
    final host = response['host'];
    final configuredUri = Uri.parse(ApiConfig.radarMetadataUrl);
    final tileHost = usesLibreWxr
        ? '${configuredUri.scheme}://${configuredUri.authority}'
        : host;
    final radar = response['radar'];
    if (host is! String || radar is! Map<String, dynamic>) {
      throw const WeatherDataException(
        WeatherDataIssue.invalidResponse,
        'Métadonnées radar incomplètes',
      );
    }
    final past = radar['past'] as List<dynamic>? ?? const [];
    final supportsChetiwaPalette =
        (radar['colorSchemes'] as List<dynamic>? ?? const []).any(
          (scheme) =>
              scheme is Map<String, dynamic> &&
              (scheme['id'] as num?)?.toInt() == 13,
        );
    final libreWxrColorScheme = supportsChetiwaPalette ? 13 : 255;
    // RainViewer retired future/nowcast frames. LibreWXR exposes a bounded
    // nowcast window, so preserve it in the direct beta path.
    final nowcast = usesLibreWxr
        ? radar['nowcast'] as List<dynamic>? ?? const []
        : const <dynamic>[];
    if (usesLibreWxr && past.isNotEmpty && response['generated'] is num) {
      final latestObservation = past
          .whereType<Map<String, dynamic>>()
          .map((frame) => frame['time'])
          .whereType<num>()
          .fold<int>(
            0,
            (latest, value) => value.toInt() > latest ? value.toInt() : latest,
          );
      final generatedAt = (response['generated'] as num).toInt();
      if (latestObservation > 0 &&
          generatedAt - latestObservation >
              const Duration(minutes: 20).inSeconds) {
        throw const WeatherDataException(
          WeatherDataIssue.providerUnavailable,
          'Observation radar trop ancienne',
        );
      }
    }
    final rawFrames = RadarFramePolicy.select(
      past
          .whereType<Map<String, dynamic>>()
          .map((frame) => (json: frame, forecast: false))
          .toList(growable: false),
      nowcast
          .whereType<Map<String, dynamic>>()
          .map((frame) => (json: frame, forecast: true))
          .toList(growable: false),
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
        final point = pointByTimestamp[timestamp.toInt()];
        final pointSource = point?['source'] as String?;
        final pointCoverage = point?['coverage'] as String?;
        final pointRate = point?['rate_mmh'];
        final hasPointValue =
            raw.forecast &&
            pointCoverage == 'in_range' &&
            pointSource != null &&
            pointSource != 'none' &&
            pointRate is num;
        return RadarFrame(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() * 1000,
            isUtc: true,
          ),
          progress: 0,
          tileUrlTemplate:
              '$tileHost$path/256/{z}/{x}/{y}/${usesLibreWxr ? '$libreWxrColorScheme/1_0' : '2/1_0'}.png',
          kind: raw.forecast
              ? WeatherDataKind.radarNowcast
              : WeatherDataKind.radarObservation,
          providerName: usesLibreWxr ? 'LibreWXR' : 'RainViewer',
          pointRainRateMmPerHour: hasPointValue ? pointRate.toDouble() : null,
          pointRainSource: hasPointValue ? pointSource : null,
        );
      }, growable: false),
    );
    await _cache.write(coordinates, frames);
    return frames;
  }
}
