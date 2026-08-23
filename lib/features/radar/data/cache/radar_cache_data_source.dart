import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/location/coordinates.dart';
import '../../../../core/storage/bounded_preference_cache.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/weather/weather_data_provenance.dart';
import '../../domain/entities/radar_frame.dart';
import '../../domain/repositories/radar_repository.dart';

final class RadarCacheDataSource {
  const RadarCacheDataSource({this.clock = const SystemWeatherClock()});

  final WeatherClock clock;

  Future<CachedRadarFrames?> read(Coordinates coordinates) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(coordinates));
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final frames = (json['frames'] as List<dynamic>)
          .map((raw) {
            final frame = raw as Map<String, dynamic>;
            return RadarFrame(
              time: DateTime.parse(frame['time'] as String),
              progress: (frame['progress'] as num).toDouble(),
              tileUrlTemplate: frame['tile_url'] as String?,
              kind: _kindFromJson(frame),
              providerName: frame['provider_name'] as String? ?? 'LibreWXR',
              pointRainRateMmPerHour: (frame['point_rain_rate_mmh'] as num?)
                  ?.toDouble(),
              pointRainSource: frame['point_rain_source'] as String?,
            );
          })
          .toList(growable: false);
      if (frames.isEmpty) return null;
      await BoundedPreferenceCache.touch(
        preferences,
        namespace: 'radar:v2',
        key: _key(coordinates),
        maxEntries: 8,
      );
      return CachedRadarFrames(
        frames: frames,
        cachedAt: DateTime.parse(json['cached_at'] as String),
      );
    } on Object {
      await BoundedPreferenceCache.forget(
        preferences,
        namespace: 'radar:v2',
        key: _key(coordinates),
      );
      return null;
    }
  }

  Future<void> write(Coordinates coordinates, List<RadarFrame> frames) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(coordinates),
      jsonEncode({
        'cached_at': clock.nowUtc.toIso8601String(),
        'frames': frames
            .map(
              (frame) => {
                'time': frame.time.toIso8601String(),
                'progress': frame.progress,
                'tile_url': frame.tileUrlTemplate,
                'kind': frame.kind.name,
                'provider_name': frame.providerName,
                'point_rain_rate_mmh': frame.pointRainRateMmPerHour,
                'point_rain_source': frame.pointRainSource,
              },
            )
            .toList(growable: false),
      }),
    );
    await BoundedPreferenceCache.touch(
      preferences,
      namespace: 'radar:v2',
      key: _key(coordinates),
      maxEntries: 8,
    );
  }

  String _key(Coordinates coordinates) =>
      'radar:v2:${coordinates.latitude.toStringAsFixed(3)}:${coordinates.longitude.toStringAsFixed(3)}';

  WeatherDataKind _kindFromJson(Map<String, dynamic> frame) {
    final name = frame['kind'] as String?;
    if (name != null) return WeatherDataKind.values.byName(name);
    return frame['is_forecast'] as bool? ?? false
        ? WeatherDataKind.radarNowcast
        : WeatherDataKind.radarObservation;
  }
}
