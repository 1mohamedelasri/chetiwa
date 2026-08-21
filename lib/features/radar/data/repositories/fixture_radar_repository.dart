import '../../../../core/location/coordinates.dart';
import '../../../../core/time/weather_clock.dart';
import '../../../../core/weather/weather_data_provenance.dart';
import '../../domain/entities/radar_frame.dart';
import '../../domain/repositories/radar_repository.dart';

final class FixtureRadarRepository implements RadarRepository {
  const FixtureRadarRepository({this.clock = const SystemWeatherClock()});

  final WeatherClock clock;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    final value = clock.nowUtc;
    final now = DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
    return List.generate(
      12,
      (index) => RadarFrame(
        time: now.add(Duration(minutes: (index - 9) * 10)),
        progress: index / 11,
        kind: index <= 9
            ? WeatherDataKind.radarObservation
            : WeatherDataKind.radarNowcast,
        providerName: 'Fixture Radar',
      ),
      growable: false,
    );
  }
}
