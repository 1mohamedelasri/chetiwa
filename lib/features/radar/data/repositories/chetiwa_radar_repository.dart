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
      final data = await _api.getData(
        '/v1/radar/frames',
        query: <String, String>{
          'latitude': coordinates.latitude.toString(),
          'longitude': coordinates.longitude.toString(),
        },
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
        return RadarFrame(
          time: DateTime.parse(frame['time'] as String).toUtc(),
          progress: mapped.length == 1 ? 1 : index / (mapped.length - 1),
          tileUrlTemplate: frame['tileUrlTemplate'] as String?,
          kind: frame['kind'] == 'nowcast'
              ? WeatherDataKind.radarNowcast
              : WeatherDataKind.radarObservation,
          providerName: providerName,
          pointRainRateMmPerHour: (frame['pointRainRateMmPerHour'] as num?)
              ?.toDouble(),
          pointRainSource: frame['pointRainSource'] as String?,
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
}
