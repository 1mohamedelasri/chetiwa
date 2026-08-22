import 'dart:convert';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/features/radar/data/cache/radar_cache_data_source.dart';
import 'package:chetiwa/features/radar/data/providers/rain_viewer_radar_provider.dart';
import 'package:chetiwa/features/radar/data/repositories/rain_viewer_radar_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('maps observation and nowcast metadata into XYZ radar frames', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'host': 'https://tiles.example',
          'radar': {
            'past': [
              {'time': 1787008800, 'path': '/v2/radar/observed'},
            ],
            'nowcast': [
              {'time': 1787009400, 'path': '/v2/radar/forecast'},
            ],
          },
        }),
        200,
      ),
    );
    final repository = RainViewerRadarRepository(
      provider: RainViewerRadarProvider(client),
      cache: const RadarCacheDataSource(),
    );

    final frames = await repository.getFrames(Coordinates.paris);
    final cached = await repository.getCachedFrames(Coordinates.paris);

    expect(frames, hasLength(2));
    expect(frames.first.kind, WeatherDataKind.radarObservation);
    expect(frames.last.kind, WeatherDataKind.radarNowcast);
    expect(frames.first.providerName, 'RainViewer');
    expect(frames.last.provenance.provider, 'RainViewer');
    expect(frames.last.tileUrlTemplate, contains('/256/{z}/{x}/{y}/2/1_0.png'));
    expect(cached?.frames, frames);
    client.close();
  });
}
