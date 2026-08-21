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

  Handler appWith(http.Client client) => createApp(
    config: config,
    providers: ProviderGateway(
      config: config,
      client: client,
      delay: (_) async {},
    ),
    now: () => instant,
  );

  test('forecast normalizes provider data and supports ETag caching', () async {
    var calls = 0;
    final app = appWith(
      MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['timeformat'], 'unixtime');
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

  test('radar frames identify observations and nowcast frames', () async {
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
    expect(frames, hasLength(2));
    expect((frames.first as Map<String, Object?>)['kind'], 'observation');
    expect((frames.last as Map<String, Object?>)['kind'], 'nowcast');
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
