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

  test('keeps LibreWXR observations and nowcast frames', () async {
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
    expect(frames.first.providerName, 'LibreWXR');
    expect(frames.first.provenance.provider, 'LibreWXR');
    expect(
      frames.first.tileUrlTemplate,
      startsWith('https://radar.ezplatforms.com/v2/radar/observed'),
    );
    expect(
      frames.first.tileUrlTemplate,
      contains('/256/{z}/{x}/{y}/10/1_1.png'),
    );
    expect(frames.last.kind, WeatherDataKind.radarNowcast);
    expect(cached?.frames, frames);
    client.close();
  });
}
