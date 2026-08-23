import 'dart:convert';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/core/weather/weather_data_health.dart';
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
      (request) async => request.method == 'POST'
          ? http.Response(
              'event: message\n'
              'data: ${jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': {
                  'structuredContent': {
                    'result': [
                      {'time': 1787009400, 'rate_mmh': 1.4, 'source': 'radar', 'coverage': 'in_range'},
                    ],
                  },
                },
              })}\n\n',
              200,
              headers: {'content-type': 'text/event-stream'},
            )
          : http.Response(
              jsonEncode({
                'host': 'https://tiles.example',
                'radar': {
                  'colorSchemes': [
                    {'id': 13, 'name': 'Chetiwa Grey Red'},
                  ],
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
      contains('/256/{z}/{x}/{y}/13/1_0.png'),
    );
    expect(frames.last.kind, WeatherDataKind.radarNowcast);
    expect(frames.last.pointRainRateMmPerHour, 1.4);
    expect(frames.last.pointRainSource, 'radar');
    expect(cached?.frames, frames);
    client.close();
  });

  test('rejects metadata whose latest observation is too old', () async {
    final client = MockClient(
      (request) async => request.method == 'POST'
          ? http.Response('{}', 200)
          : http.Response(
              jsonEncode({
                'generated': 1787010601,
                'host': 'https://tiles.example',
                'radar': {
                  'past': [
                    {'time': 1787008800, 'path': '/v2/radar/stale'},
                  ],
                  'nowcast': const [],
                },
              }),
              200,
            ),
    );
    final repository = RainViewerRadarRepository(
      provider: RainViewerRadarProvider(client),
      cache: const RadarCacheDataSource(),
    );

    await expectLater(
      repository.getFrames(Coordinates.paris),
      throwsA(
        isA<WeatherDataException>().having(
          (error) => error.issue,
          'issue',
          WeatherDataIssue.providerUnavailable,
        ),
      ),
    );
    client.close();
  });

  test(
    'uses the visible intensity palette before the custom LUT rollout',
    () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'generated': 1787009401,
            'host': 'https://tiles.example',
            'radar': {
              'colorSchemes': [
                {'id': 12, 'name': '33/40 Max Storm'},
              ],
              'past': [
                {'time': 1787008800, 'path': '/v2/radar/observed'},
              ],
              'nowcast': const [],
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
      expect(frames.single.tileUrlTemplate, contains('/12/1_0.png'));
      client.close();
    },
  );
}
