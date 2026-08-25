import 'dart:convert';
import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late DateTime instant;
  late RuntimeConfig config;

  setUp(() {
    instant = DateTime.utc(2026, 8, 20, 18);
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
    });
  });

  Handler appWith(http.Client client, {RadarQuotaTracker? radarQuota}) =>
      createApp(
        config: config,
        providers: ProviderGateway(
          config: config,
          client: client,
          delay: (_) async {},
        ),
        now: () => instant,
        radarQuota: radarQuota,
      );

  test(
    'public app config fails closed and requires an installation id',
    () async {
      final app = appWith(MockClient((_) async => http.Response('{}', 200)));
      final uri = Uri.parse('http://localhost/v1/app-config');

      final unauthorized = await app(Request('GET', uri));
      expect(unauthorized.statusCode, 401);

      final response = await app(
        Request(
          'GET',
          uri,
          headers: const <String, String>{
            'x-chetiwa-device-id': 'test-installation-1234',
          },
        ),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      final data = body['data'] as Map<String, Object?>;
      expect(data['features'], <String, Object?>{
        'premium': false,
        'premiumSatellite': false,
        'premiumRadarModel': false,
        'ads': false,
      });
    },
  );

  test('premium rollout is stable per installation', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'PREMIUM_ENABLED': 'true',
      'PREMIUM_ROLLOUT_PERCENT': '100',
      'PREMIUM_SATELLITE_ENABLED': 'true',
      'PREMIUM_RADAR_MODEL_ENABLED': 'true',
      'ADS_ENABLED': 'true',
      'ARCGIS_API_KEY': 'test-key',
    });
    final app = appWith(MockClient((_) async => http.Response('{}', 200)));
    final response = await app(
      Request(
        'GET',
        Uri.parse('http://localhost/v1/app-config'),
        headers: const <String, String>{
          'x-chetiwa-device-id': 'stable-installation-1234',
        },
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final data = body['data'] as Map<String, Object?>;
    expect(data['features'], <String, Object?>{
      'premium': true,
      'premiumSatellite': true,
      'premiumRadarModel': true,
      'ads': true,
    });
  });

  test('forecast normalizes provider data and supports ETag caching', () async {
    var calls = 0;
    final app = appWith(
      MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['timeformat'], 'unixtime');
        expect(request.url.path, '/v1/meteofrance');
        return http.Response(jsonEncode(_forecastFixture), 200);
      }),
    );
    final uri = Uri.parse(
      'http://localhost/v1/forecast?latitude=48.8566&longitude=2.3522',
    );

    final first = await app(Request('GET', uri));
    final firstBody =
        jsonDecode(await first.readAsString()) as Map<String, Object?>;
    final firstData = firstBody['data'] as Map<String, Object?>;
    final current = firstData['current'] as Map<String, Object?>;

    expect(first.statusCode, 200);
    expect(first.headers['x-cache'], 'MISS');
    expect(current['temperatureCelsius'], 22.4);
    expect((firstData['hourly'] as List<Object?>), hasLength(2));
    expect(calls, 1);

    final second = await app(Request('GET', uri));
    expect(second.statusCode, 200);
    expect(second.headers['x-cache'], 'HIT');
    expect(calls, 1);

    final conditional = await app(
      Request(
        'GET',
        uri,
        headers: <String, String>{'if-none-match': first.headers['etag']!},
      ),
    );
    expect(conditional.statusCode, 304);
    expect(await conditional.readAsString(), isEmpty);
    expect(calls, 1);
  });

  test('forecast serves stale data when its provider is unavailable', () async {
    var succeeds = true;
    final app = appWith(
      MockClient(
        (request) async => succeeds
            ? http.Response(jsonEncode(_forecastFixture), 200)
            : http.Response('unavailable', 503),
      ),
    );
    final uri = Uri.parse(
      'http://localhost/v1/forecast?latitude=48.8566&longitude=2.3522',
    );

    final first = await app(Request('GET', uri));
    expect(first.statusCode, 200);
    succeeds = false;
    instant = instant.add(const Duration(minutes: 6));

    final stale = await app(Request('GET', uri));
    expect(stale.statusCode, 200);
    expect(stale.headers['x-cache'], 'STALE');
    expect(stale.headers['warning'], contains('Response is stale'));
  });

  test('location search returns the stable Chetiwa contract', () async {
    final app = appWith(
      MockClient((request) async {
        expect(request.url.path, '/v1/search');
        expect(request.url.queryParameters['language'], 'en');
        return http.Response(
          jsonEncode(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'name': 'Paris',
                'country': 'France',
                'admin1': 'Île-de-France',
                'latitude': 48.8566,
                'longitude': 2.3522,
                'timezone': 'Europe/Paris',
              },
            ],
          }),
          200,
        );
      }),
    );

    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/locations/search?q=Paris&language=en&count=5',
        ),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final data = body['data'] as Map<String, Object?>;
    final location =
        (data['locations'] as List<Object?>).single as Map<String, Object?>;

    expect(response.statusCode, 200);
    expect(location['name'], 'Paris');
    expect(location['timeZone'], 'Europe/Paris');
  });

  test('reverse geocoding does not expose the provider credential', () async {
    final app = appWith(
      MockClient((request) async {
        expect(request.url.queryParameters['token'], 'test-key');
        return http.Response(
          jsonEncode(<String, Object?>{
            'address': <String, Object?>{
              'City': 'Bruxelles',
              'CountryCode': 'BEL',
              'Region': 'Bruxelles-Capitale',
            },
            'location': <String, Object?>{'x': 4.3517, 'y': 50.8503},
          }),
          200,
        );
      }),
    );
    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/locations/reverse?latitude=50.8503&longitude=4.3517',
        ),
      ),
    );
    final text = await response.readAsString();

    expect(response.statusCode, 200);
    expect(text, contains('Bruxelles'));
    expect(text, isNot(contains('test-key')));
  });

  test('LibreWXR radar exposes observations and nowcast frames', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_PROVIDER': 'librewxr',
      'RADAR_METADATA_URL':
          'https://radar.ezplatforms.com/public/weather-maps.json',
      'PREMIUM_RADAR_MODEL_ENABLED': 'true',
    });
    final app = appWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode(<String, Object?>{
            'host': 'https://tile.example.test',
            'radar': <String, Object?>{
              'past': <Object?>[
                <String, Object?>{'time': 1776707400, 'path': '/past'},
              ],
              'nowcast': <Object?>[
                <String, Object?>{'time': 1776708000, 'path': '/future'},
                <String, Object?>{'time': 1776711600, 'path': '/future-model'},
              ],
            },
          }),
          200,
        ),
      ),
    );
    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/radar/frames?latitude=52.52&longitude=13.405',
        ),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final data = body['data'] as Map<String, Object?>;
    final frames = data['frames'] as List<Object?>;

    expect(response.statusCode, 200);
    expect(frames, hasLength(3));
    expect((frames.first as Map<String, Object?>)['kind'], 'observation');
    expect((frames[1] as Map<String, Object?>)['kind'], 'nowcast');
    expect((frames.last as Map<String, Object?>)['kind'], 'model');
    expect(
      (frames[1] as Map<String, Object?>)['tileUrlTemplate'],
      'https://radar.ezplatforms.com/future/256/{z}/{x}/{y}/13/1_0.png',
    );
    expect((data['provider'] as Map<String, Object?>)['id'], 'librewxr');
  });

  test('model radar frames fail closed behind the premium flag', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_PROVIDER': 'librewxr',
      'RADAR_METADATA_URL':
          'https://radar.ezplatforms.com/public/weather-maps.json',
    });
    final app = appWith(
      MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'host': 'https://tile.example.test',
            'radar': <String, Object?>{
              'past': <Object?>[
                <String, Object?>{'time': 1776707400, 'path': '/past'},
              ],
              'nowcast': <Object?>[
                <String, Object?>{'time': 1776708000, 'path': '/future'},
                <String, Object?>{'time': 1776711600, 'path': '/future-model'},
              ],
            },
          }),
          200,
        ),
      ),
    );

    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/radar/frames?latitude=48.85&longitude=2.35',
        ),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final data = body['data'] as Map<String, Object?>;
    final frames = data['frames'] as List<Object?>;

    expect(frames, hasLength(2));
    expect(
      frames.whereType<Map<String, Object?>>().any(
        (frame) => frame['kind'] == 'model',
      ),
      isFalse,
    );
  });

  test(
    'Radar sessions are explicit, idempotent and non-blocking in beta',
    () async {
      config = RuntimeConfig.fromEnvironment(const <String, String>{
        'ARCGIS_API_KEY': 'test-key',
        'RADAR_FREE_SESSIONS': '1',
        'RADAR_QUOTA_ENFORCED': 'false',
      });
      final tracker = RadarQuotaTracker(
        policy: const RadarQuotaPolicy(freeSessions: 1, premiumSessions: 2),
      );
      final app = appWith(
        MockClient((_) async => http.Response('{}', 200)),
        radarQuota: tracker,
      );
      const installationId = 'installation-1234567890';

      Future<Map<String, Object?>> open(String sessionId) async {
        final response = await app(
          Request(
            'POST',
            Uri.parse('http://localhost/v1/radar/sessions'),
            headers: <String, String>{
              'x-chetiwa-device-id': installationId,
              'x-chetiwa-radar-session-id': sessionId,
              'x-chetiwa-plan': 'free',
            },
          ),
        );
        expect(response.statusCode, 201);
        final body =
            jsonDecode(await response.readAsString()) as Map<String, Object?>;
        return (body['data'] as Map<String, Object?>)['session']
            as Map<String, Object?>;
      }

      final first = await open('radar-session-00000001');
      final retry = await open('radar-session-00000001');
      final overLimit = await open('radar-session-00000002');

      expect(first['used'], 1);
      expect(retry['used'], 1);
      expect(overLimit['used'], 2);
      expect(overLimit['overLimit'], isTrue);
      expect(overLimit['enforced'], isFalse);
      expect(overLimit['allowed'], isTrue);
    },
  );

  test('Radar frame refreshes never consume session quota', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_FREE_SESSIONS': '1',
    });
    final tracker = RadarQuotaTracker(
      policy: const RadarQuotaPolicy(freeSessions: 1, premiumSessions: 2),
    );
    final app = appWith(
      MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'host': 'https://radar.ezplatforms.com',
            'radar': <String, Object?>{
              'past': <Object?>[
                <String, Object?>{
                  'time': 1776707400,
                  'path': '/v2/radar/observed',
                },
              ],
              'nowcast': const <Object?>[],
            },
          }),
          200,
        ),
      ),
      radarQuota: tracker,
    );
    final framesUri = Uri.parse(
      'http://localhost/v1/radar/frames?latitude=48.85&longitude=2.35',
    );

    for (var index = 0; index < 25; index++) {
      final response = await app(Request('GET', framesUri));
      expect(response.statusCode, 200);
    }
    final session = await app(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/radar/sessions'),
        headers: const <String, String>{
          'x-chetiwa-device-id': 'installation-1234567890',
          'x-chetiwa-radar-session-id': 'radar-session-after-refreshes',
        },
      ),
    );
    final body =
        jsonDecode(await session.readAsString()) as Map<String, Object?>;
    final data = body['data'] as Map<String, Object?>;
    final decision = data['session'] as Map<String, Object?>;

    expect(session.statusCode, 201);
    expect(decision['used'], 1);
    expect(decision['remaining'], 0);
  });

  test('LibreWXR point nowcast is normalized and cached by location', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_PROVIDER': 'librewxr',
      'RADAR_METADATA_URL':
          'https://radar.ezplatforms.com/public/weather-maps.json',
    });
    var providerCalls = 0;
    final app = appWith(
      MockClient((request) async {
        providerCalls++;
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://radar.ezplatforms.com/mcp/'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final params = body['params'] as Map<String, dynamic>;
        final arguments = params['arguments'] as Map<String, dynamic>;
        expect(arguments['lat'], 48.8566);
        expect(arguments['lon'], 2.3522);
        expect(arguments['minutes'], 60);
        return http.Response(
          'event: message\n'
          'data: ${jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{
              'structuredContent': <String, Object?>{
                'result': <Object?>[
                  <String, Object?>{'time': 1776708000, 'rate_mmh': 1.4, 'source': 'radar', 'coverage': 'in_range'},
                ],
              },
            },
          })}\n\n',
          200,
          headers: const <String, String>{'content-type': 'text/event-stream'},
        );
      }),
    );
    final uri = Uri.parse(
      'http://localhost/v1/radar/point-nowcast'
      '?latitude=48.8566&longitude=2.3522',
    );

    final first = await app(Request('GET', uri));
    final firstBody =
        jsonDecode(await first.readAsString()) as Map<String, Object?>;
    final firstData = firstBody['data'] as Map<String, Object?>;
    final sample =
        (firstData['samples'] as List<Object?>).single as Map<String, Object?>;
    final second = await app(Request('GET', uri));

    expect(first.statusCode, 200);
    expect(first.headers['x-cache'], 'MISS');
    expect(sample['time'], '2026-04-20T18:00:00.000Z');
    expect(sample['rainRateMmPerHour'], 1.4);
    expect(sample['source'], 'radar');
    expect(sample['coverage'], 'in_range');
    expect(second.statusCode, 200);
    expect(second.headers['x-cache'], 'HIT');
    expect(providerCalls, 1);
  });

  test('RainViewer radar frames remain observations only', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_PROVIDER': 'rainviewer',
      'RADAR_METADATA_URL':
          'https://api.rainviewer.com/public/weather-maps.json',
    });
    final app = appWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode(<String, Object?>{
            'host': 'https://tile.example.test',
            'radar': <String, Object?>{
              'past': <Object?>[
                <String, Object?>{'time': 1776707400, 'path': '/past'},
              ],
              'nowcast': <Object?>[
                <String, Object?>{'time': 1776708000, 'path': '/future'},
              ],
            },
          }),
          200,
        ),
      ),
    );
    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/radar/frames?latitude=52.52&longitude=13.405',
        ),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final data = body['data'] as Map<String, Object?>;
    final frames = data['frames'] as List<Object?>;

    expect(response.statusCode, 200);
    expect(frames, hasLength(1));
    expect((frames.single as Map<String, Object?>)['kind'], 'observation');
  });

  test('LibreWXR tile proxy returns a decodable PNG with palette 13', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_PROVIDER': 'librewxr',
      'RADAR_TILE_URL_TEMPLATE':
          'https://radar.ezplatforms.com{frame}/256/{z}/{x}/{y}/13/1_0.png',
    });
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+3MxZ5wAAAABJRU5ErkJggg==',
    );
    String? requestedPath;
    final app = appWith(
      MockClient((request) async {
        requestedPath = request.url.path;
        return http.Response.bytes(
          png,
          200,
          headers: const <String, String>{'content-type': 'image/png'},
        );
      }),
    );
    final frame = base64Url
        .encode(utf8.encode('/v2/radar/observed'))
        .replaceAll('=', '');

    final response = await app(
      Request(
        'GET',
        Uri.parse('http://localhost/v1/radar/tiles/$frame/7/64/44'),
      ),
    );
    final bytes = await response.read().expand((chunk) => chunk).toList();

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'image/png');
    expect(requestedPath, '/v2/radar/observed/256/7/64/44/13/1_0.png');
    expect(bytes, orderedEquals(png));
    expect(
      bytes.take(8),
      orderedEquals(const <int>[
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
    );
  });

  test('Radar tile proxy serves stale PNG after an origin 502', () async {
    config = RuntimeConfig.fromEnvironment(const <String, String>{
      'ARCGIS_API_KEY': 'test-key',
      'RADAR_PROVIDER': 'librewxr',
      'RADAR_TILE_URL_TEMPLATE':
          'https://radar.ezplatforms.com{frame}/256/{z}/{x}/{y}/13/1_0.png',
    });
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+3MxZ5wAAAABJRU5ErkJggg==',
    );
    var originAvailable = true;
    final app = appWith(
      MockClient(
        (_) async => originAvailable
            ? http.Response.bytes(
                png,
                200,
                headers: const <String, String>{'content-type': 'image/png'},
              )
            : http.Response('tunnel unavailable', 502),
      ),
    );
    final frame = base64Url
        .encode(utf8.encode('/v2/radar/observed'))
        .replaceAll('=', '');
    final uri = Uri.parse('http://localhost/v1/radar/tiles/$frame/7/64/44');

    final first = await app(Request('GET', uri));
    expect(first.statusCode, 200);
    expect(first.headers['x-cache'], 'MISS');
    await first.read().drain<void>();
    originAvailable = false;
    instant = instant.add(const Duration(hours: 7));

    final stale = await app(Request('GET', uri));
    final bytes = await stale.read().expand((chunk) => chunk).toList();

    expect(stale.statusCode, 200);
    expect(stale.headers['x-cache'], 'STALE');
    expect(stale.headers['warning'], contains('Response is stale'));
    expect(bytes, orderedEquals(png));
  });

  test('invalid public input returns a stable 400 error', () async {
    final app = appWith(
      MockClient((request) async => http.Response('{}', 200)),
    );
    final response = await app(
      Request(
        'GET',
        Uri.parse('http://localhost/v1/forecast?latitude=200&longitude=2'),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final error = body['error'] as Map<String, Object?>;

    expect(response.statusCode, 400);
    expect(error['code'], 'invalid_latitude');
  });

  test('an incomplete provider payload is rejected as a 502', () async {
    final app = appWith(
      MockClient((request) async => http.Response('{}', 200)),
    );
    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/forecast?latitude=48.8566&longitude=2.3522',
        ),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final error = body['error'] as Map<String, Object?>;

    expect(response.statusCode, 502);
    expect(error['code'], 'invalid_forecast_response');
  });

  test('large JSON responses use gzip when the client accepts it', () async {
    final app = appWith(
      MockClient(
        (request) async => http.Response(jsonEncode(_forecastFixture), 200),
      ),
    );
    final response = await app(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/v1/forecast?latitude=48.8566&longitude=2.3522',
        ),
        headers: const <String, String>{'accept-encoding': 'br, gzip'},
      ),
    );
    final compressed = await response.read().expand((chunk) => chunk).toList();
    final decoded = utf8.decode(gzip.decode(compressed));

    expect(response.statusCode, 200);
    expect(response.headers['content-encoding'], 'gzip');
    expect(response.headers['vary'], contains('accept-encoding'));
    expect(jsonDecode(decoded), isA<Map<String, Object?>>());
  });

  test('versioned routes enforce the per-client request limit', () async {
    final app = createApp(
      config: config,
      providers: ProviderGateway(
        config: config,
        client: MockClient(
          (request) async => http.Response(jsonEncode(_forecastFixture), 200),
        ),
      ),
      rateLimiter: RequestRateLimiter(limit: 2),
      now: () => instant,
    );
    final uri = Uri.parse(
      'http://localhost/v1/forecast?latitude=48.8566&longitude=2.3522',
    );
    const headers = <String, String>{'x-chetiwa-device-id': 'test-device-0001'};

    expect((await app(Request('GET', uri, headers: headers))).statusCode, 200);
    expect((await app(Request('GET', uri, headers: headers))).statusCode, 200);
    final blocked = await app(Request('GET', uri, headers: headers));

    expect(blocked.statusCode, 429);
    expect(blocked.headers['retry-after'], '60');
    expect(blocked.headers['x-ratelimit-remaining'], '0');
  });

  test('radar tiles use a separate higher-capacity request bucket', () async {
    final app = createApp(
      config: config,
      providers: ProviderGateway(
        config: config,
        client: MockClient(
          (request) async => http.Response(jsonEncode(_forecastFixture), 200),
        ),
      ),
      rateLimiter: RequestRateLimiter(limit: 1),
      tileRateLimiter: RequestRateLimiter(limit: 2),
      now: () => instant,
    );
    const headers = <String, String>{'x-chetiwa-device-id': 'test-device-0002'};
    final forecastUri = Uri.parse(
      'http://localhost/v1/forecast?latitude=48.8566&longitude=2.3522',
    );
    final frame = base64Url
        .encode(utf8.encode('/v2/radar/rate-limit-test'))
        .replaceAll('=', '');
    final tileUri = Uri.parse('http://localhost/v1/radar/tiles/$frame/7/64/44');

    expect(
      (await app(Request('GET', forecastUri, headers: headers))).statusCode,
      200,
    );
    expect(
      (await app(Request('GET', forecastUri, headers: headers))).statusCode,
      429,
    );
    expect(
      (await app(Request('GET', tileUri, headers: headers))).statusCode,
      isNot(429),
    );
    expect(
      (await app(Request('GET', tileUri, headers: headers))).statusCode,
      isNot(429),
    );
    final blockedTile = await app(Request('GET', tileUri, headers: headers));
    expect(blockedTile.statusCode, 429);
    expect(blockedTile.headers['x-ratelimit-limit'], '2');
  });
}

const _forecastFixture = <String, Object?>{
  'timezone': 'Europe/Paris',
  'utc_offset_seconds': 7200,
  'current': <String, Object?>{
    'time': 1776708000,
    'temperature_2m': 22.4,
    'weather_code': 61,
    'precipitation': 0.8,
    'wind_speed_10m': 16.0,
  },
  'minutely_15': <String, Object?>{
    'time': <Object?>[1776708000, 1776708900],
    'precipitation': <Object?>[0.2, 0.0],
  },
  'hourly': <String, Object?>{
    'time': <Object?>[1776708000, 1776711600],
    'temperature_2m': <Object?>[22.4, 21.0],
    'weather_code': <Object?>[61, 3],
    'precipitation_probability': <Object?>[80, 20],
    'precipitation': <Object?>[0.8, 0.0],
    'wind_speed_10m': <Object?>[16.0, 14.0],
  },
  'daily': <String, Object?>{
    'time': <Object?>[1776643200],
    'weather_code': <Object?>[61],
    'temperature_2m_max': <Object?>[24.0],
    'temperature_2m_min': <Object?>[17.0],
    'precipitation_probability_max': <Object?>[80],
    'sunrise': <Object?>[1776661200],
    'sunset': <Object?>[1776712200],
  },
};
