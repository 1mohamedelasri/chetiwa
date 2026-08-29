import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 29, 21, 30);

  test('loads and parses an official MeteoGate warning polygon', () async {
    var gatewayRequests = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.meteogate.eu') {
        gatewayRequests += 1;
        expect(request.headers['apikey'], 'meteogate-key');
        expect(request.url.queryParameters['active'], now.toIso8601String());
        expect(request.url.queryParameters['page'], '1');
        return http.Response(
          jsonEncode(<String, Object?>{
            'type': 'FeatureCollection',
            'features': <Object?>[
              <String, Object?>{
                'id': 'feature-1',
                'type': 'Feature',
                'properties': <String, Object?>{
                  'OBJECTID': 'feature-1',
                  'alertId': 'alert-1',
                  'indexArea': 0,
                  'indexInfo': 0,
                  'hubTime': now
                      .subtract(const Duration(minutes: 10))
                      .toIso8601String(),
                },
                'links': <Object?>[
                  <String, Object?>{
                    'type': 'application/json',
                    'href':
                        'https://meteo.fra1.digitaloceanspaces.com/cap.json',
                  },
                  <String, Object?>{
                    'type': 'application/geo+json',
                    'href':
                        'https://meteo.fra1.digitaloceanspaces.com/area.geojson',
                  },
                ],
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/cap.json') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'identifier': 'alert-1',
            'sent': now.subtract(const Duration(minutes: 10)).toIso8601String(),
            'info': <Object?>[
              <String, Object?>{
                'language': 'fr',
                'onset': now
                    .subtract(const Duration(minutes: 5))
                    .toIso8601String(),
                'expires': now.add(const Duration(hours: 2)).toIso8601String(),
                'parameter': <Object?>[
                  <String, Object?>{
                    'valueName': 'awareness_level',
                    'value': '3; orange; Severe',
                  },
                  <String, Object?>{
                    'valueName': 'awareness_type',
                    'value': '10; Rain',
                  },
                ],
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/area.geojson') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'type': 'Feature',
            'properties': const <String, Object?>{},
            'geometry': <String, Object?>{
              'type': 'Polygon',
              'coordinates': <Object?>[
                <Object?>[
                  <num>[4.1, 50.7],
                  <num>[4.6, 50.7],
                  <num>[4.6, 51.1],
                  <num>[4.1, 51.1],
                  <num>[4.1, 50.7],
                ],
              ],
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final provider = MeteoAlarmVigilanceProvider(
      client: client,
      apiKey: 'meteogate-key',
      now: () => now,
    );

    final snapshot = await provider.current();

    expect(gatewayRequests, 1);
    expect(snapshot.events, hasLength(1));
    final event = snapshot.events.single;
    expect(event.level, VigilanceLevel.orange);
    expect(event.phenomenon, VigilancePhenomenon.rainFlood);
    expect(event.contains(latitude: 50.85, longitude: 4.35), isTrue);
    expect(event.contains(latitude: 48.85, longitude: 2.35), isFalse);
  });

  test('treats a 204 response as a valid empty snapshot', () async {
    final provider = MeteoAlarmVigilanceProvider(
      client: MockClient((_) async => http.Response('', 204)),
      apiKey: 'meteogate-key',
      now: () => now,
    );

    final snapshot = await provider.current();

    expect(snapshot.events, isEmpty);
    expect(snapshot.productAt, now);
  });
}
