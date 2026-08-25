import '../../../../core/location/coordinates.dart';
import '../../../../core/network/chetiwa_api_client.dart';
import '../../../../core/weather/weather_data_health.dart';
import '../../../../core/weather/weather_data_provenance.dart';
import '../../domain/entities/radar_frame.dart';
import '../../domain/repositories/radar_repository.dart';
import '../cache/radar_cache_data_source.dart';

final class ChetiwaRadarRepository implements RadarRepository {
  const ChetiwaRadarRepository({
    required ChetiwaApiClient api,
    required RadarCacheDataSource cache,
  }) : _api = api,
       _cache = cache;

  final ChetiwaApiClient _api;
  final RadarCacheDataSource _cache;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) =>
      _cache.read(coordinates);

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    try {
      final query = <String, String>{
        'latitude': coordinates.latitude.toString(),
        'longitude': coordinates.longitude.toString(),
      };
      // Point sampling enriches Graph but must never make the radar tile
      // timeline unavailable. Start both calls together and degrade to model
      // data when the optional point endpoint fails.
      final pointSamplesFuture = _getPointSamples(query);
      final data = await _api.getData('/v1/radar/frames', query: query);
      final pointSamples = await pointSamplesFuture.timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => const <int, _PointSample>{},
      );
      final rawFrames = data['frames'] as List<dynamic>? ?? const [];
      final provider = data['provider'] as Map<String, dynamic>?;
      final providerName = '${provider?['id'] ?? 'radar'} via Chetiwa';
      final mapped = rawFrames.whereType<Map<String, dynamic>>().toList();
      if (mapped.isEmpty) {
        throw const WeatherDataException(
          WeatherDataIssue.noRadarCoverage,
          'Aucune image radar disponible pour cette zone',
        );
      }
      final frames = List<RadarFrame>.generate(mapped.length, (index) {
        final frame = mapped[index];
        final time = DateTime.parse(frame['time'] as String).toUtc();
        final point = pointSamples[time.millisecondsSinceEpoch];
        return RadarFrame(
          time: time,
          progress: mapped.length == 1 ? 1 : index / (mapped.length - 1),
          tileUrlTemplate: frame['tileUrlTemplate'] as String?,
          kind: switch (frame['kind']) {
            'nowcast' => WeatherDataKind.radarNowcast,
            'model' => WeatherDataKind.modelForecast,
            _ => WeatherDataKind.radarObservation,
          },
          providerName: providerName,
          pointRainRateMmPerHour: frame['kind'] == 'nowcast'
              ? point?.rainRateMmPerHour ??
                    (frame['pointRainRateMmPerHour'] as num?)?.toDouble()
              : null,
          pointRainSource: frame['kind'] == 'nowcast'
              ? point?.source ?? frame['pointRainSource'] as String?
              : null,
        );
      }, growable: false);
      await _cache.write(coordinates, frames);
      return frames;
    } on WeatherDataException {
      rethrow;
    } on ChetiwaApiException catch (error) {
      throw WeatherDataException(
        error.isNetworkFailure
            ? WeatherDataIssue.offline
            : WeatherDataIssue.providerUnavailable,
        error.message,
      );
    } on Object {
      throw const WeatherDataException(
        WeatherDataIssue.invalidResponse,
        'Réponse radar Chetiwa invalide',
      );
    }
  }

  Future<Map<int, _PointSample>> _getPointSamples(
    Map<String, String> query,
  ) async {
    try {
      final data = await _api.getData('/v1/radar/point-nowcast', query: query);
      final samples = data['samples'] as List<dynamic>? ?? const [];
      return <int, _PointSample>{
        for (final sample in samples.whereType<Map<String, dynamic>>())
          if (sample['time'] is String &&
              sample['rainRateMmPerHour'] is num &&
              sample['source'] is String &&
              sample['source'] != 'none' &&
              sample['coverage'] == 'in_range')
            DateTime.parse(
              sample['time'] as String,
            ).toUtc().millisecondsSinceEpoch: _PointSample(
              rainRateMmPerHour: (sample['rainRateMmPerHour'] as num)
                  .toDouble(),
              source: sample['source'] as String,
            ),
      };
    } on Object {
      return const <int, _PointSample>{};
    }
  }
}

final class _PointSample {
  const _PointSample({required this.rainRateMmPerHour, required this.source});

  final double rainRateMmPerHour;
  final String source;
}
