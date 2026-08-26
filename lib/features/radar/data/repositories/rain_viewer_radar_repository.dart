import 'dart:math' as math;

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
    this.pointEnrichmentBudget = const Duration(milliseconds: 1200),
  }) : _provider = provider,
       _cache = cache;

  final RainViewerRadarProvider _provider;
  final RadarCacheDataSource _cache;
  final Duration pointEnrichmentBudget;

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
    // Point sampling enriches Graph but must never hold the primary radar
    // image hostage. LibreWXR's MCP endpoint can take up to eight seconds on a
    // cold worker; use the model-labelled Graph fallback after a short budget.
    final pointNowcast = await pointNowcastFuture.timeout(
      pointEnrichmentBudget,
      onTimeout: () => const <Map<String, dynamic>>[],
    );
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
    final supportedColorSchemeIds =
        (radar['colorSchemes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((scheme) => (scheme['id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
    // During the rollout, scheme 255 is the raw/grey presentation and hides
    // the intensity contrast users need to compare with other radar apps.
    // Scheme 12 is already exposed by LibreWXR and keeps yellow/red cores
    // visible until the Chetiwa grey/red LUT (13) is installed.
    final libreWxrColorScheme = supportedColorSchemeIds.contains(14)
        ? 14
        : supportedColorSchemeIds.contains(13)
        ? 13
        : 12;
    // RainViewer retired future/nowcast frames. LibreWXR exposes a bounded
    // nowcast window, so preserve it in the direct beta path.
    final nowcast = usesLibreWxr
        ? radar['nowcast'] as List<dynamic>? ?? const []
        : const <dynamic>[];
    final firstNowcastEpoch = nowcast
        .whereType<Map<String, dynamic>>()
        .map((frame) => frame['time'])
        .whereType<num>()
        .map((value) => value.toInt())
        .fold<int?>(
          null,
          (first, value) => first == null || value < first ? value : first,
        );
    final latestRawObservationEpoch = past
        .whereType<Map<String, dynamic>>()
        .map((frame) => frame['time'])
        .whereType<num>()
        .fold<int>(0, (latest, value) => math.max(latest, value.toInt()));
    final lastNowcastEpoch = nowcast
        .whereType<Map<String, dynamic>>()
        .map((frame) => frame['time'])
        .whereType<num>()
        .fold<int>(0, (latest, value) => math.max(latest, value.toInt()));
    final horizonAnchorEpoch =
        lastNowcastEpoch - const Duration(minutes: 120).inSeconds;
    final hasHorizonAnchor =
        horizonAnchorEpoch > 0 &&
        past.whereType<Map<String, dynamic>>().any(
          (frame) => (frame['time'] as num?)?.toInt() == horizonAnchorEpoch,
        );
    final nowcastRunEpoch = hasHorizonAnchor
        ? horizonAnchorEpoch
        : firstNowcastEpoch == null
        ? 0
        : past
              .whereType<Map<String, dynamic>>()
              .map((frame) => frame['time'])
              .whereType<num>()
              .map((value) => value.toInt())
              .where((value) => value < firstNowcastEpoch)
              .fold<int>(0, math.max);
    final latestObservationEpoch = nowcastRunEpoch > 0
        ? nowcastRunEpoch
        : latestRawObservationEpoch;
    final timelinePast = latestObservationEpoch == 0
        ? past
        : past
              .whereType<Map<String, dynamic>>()
              .where((frame) {
                final time = frame['time'];
                return time is num && time.toInt() <= latestObservationEpoch;
              })
              .toList(growable: false);
    if (usesLibreWxr && past.isNotEmpty && response['generated'] is num) {
      final generatedAt = (response['generated'] as num).toInt();
      if (latestRawObservationEpoch > 0 &&
          generatedAt - latestRawObservationEpoch >
              const Duration(minutes: 20).inSeconds) {
        throw const WeatherDataException(
          WeatherDataIssue.providerUnavailable,
          'Observation radar trop ancienne',
        );
      }
    }
    final rawFrames = RadarFramePolicy.select(
      timelinePast
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
          // LibreWXR regenerates a future valid-time on every observation
          // cycle while keeping the same timestamp path. Include the source
          // observation in forecast URLs so Cloudflare and the persistent
          // mobile cache cannot keep an older forecast for up to six hours.
          tileUrlTemplate:
              '$tileHost$path/256/{z}/{x}/{y}/${usesLibreWxr ? '$libreWxrColorScheme/1_0' : '2/1_0'}.png${usesLibreWxr ? '?presentation=crisp-v2${raw.forecast && latestObservationEpoch > 0 ? '&run=$latestObservationEpoch' : ''}' : ''}',
          kind: raw.forecast && latestObservationEpoch > 0
              ? RadarFramePolicy.futureKind(
                  latestObservation: DateTime.fromMillisecondsSinceEpoch(
                    latestObservationEpoch * 1000,
                    isUtc: true,
                  ),
                  forecastTime: DateTime.fromMillisecondsSinceEpoch(
                    timestamp.toInt() * 1000,
                    isUtc: true,
                  ),
                )
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
