import 'dart:convert';

import 'package:chetiwa/core/network/chetiwa_api_client.dart';
import 'package:chetiwa/core/notifications/firebase_push_messaging.dart';
import 'package:chetiwa/features/alerts/application/remote_rain_alert_gateway.dart';
import 'package:chetiwa/features/alerts/data/chetiwa_alert_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('registers one anonymous device and one remote rule', () async {
    final requests = <http.Request>[];
    final messaging = FixturePushMessagingGateway(token: 'fcm-token');
    final gateway = ChetiwaRemoteRainAlertGateway(
      api: ChetiwaAlertApi(
        ChetiwaApiClient(
          baseUri: Uri.parse('https://api.chetiwa.test/'),
          client: MockClient((request) async {
            requests.add(request);
            if (request.method == 'DELETE') return http.Response('', 204);
            if (request.method == 'GET') {
              return _response(<String, Object?>{'alerts': <Object?>[]});
            }
            if (request.url.path == '/v1/devices') {
              return _response(<String, Object?>{
                'device': <String, Object?>{'registered': true},
              }, status: 201);
            }
            return _response(<String, Object?>{
              'alert': _alertJson(),
            }, status: 201);
          }),
        ),
      ),
      messaging: messaging,
      phoneTimeZone: () async => 'Europe/Paris',
      appVersion: () async => '1.0.0+7',
      platform: () => 'android',
      locale: () => 'fr',
    );

    final result = await gateway.syncRule(
      location: const AlertLocationInput(
        label: 'Paris, France',
        latitude: 48.8566,
        longitude: 2.3522,
        timeZone: 'Europe/Paris',
      ),
      leadMinutes: 15,
      minimumIntensity: RainAlertIntensity.moderate,
      quietHours: const AlertQuietHoursInput(
        enabled: true,
        start: '22:00',
        end: '07:00',
      ),
    );

    expect(result, RemoteRainAlertSyncResult.registered);
    expect(requests.map((request) => request.method), <String>[
      'POST',
      'GET',
      'POST',
    ]);
    final registration =
        jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(registration['pushToken'], 'fcm-token');
    expect(registration['timeZone'], 'Europe/Paris');
    expect(registration['appVersion'], '1.0.0+7');
    expect(
      requests.first.headers['x-chetiwa-device-id'],
      matches(r'^[a-f0-9]{32}$'),
    );

    expect(await gateway.deactivate(), isTrue);
    expect(messaging.disabled, isTrue);
    expect(requests.last.method, 'DELETE');
  });

  test(
    'keeps local fallback when notification authorization is absent',
    () async {
      var requests = 0;
      final gateway = ChetiwaRemoteRainAlertGateway(
        api: ChetiwaAlertApi(
          ChetiwaApiClient(
            baseUri: Uri.parse('https://api.chetiwa.test/'),
            client: MockClient((request) async {
              requests += 1;
              return http.Response('', 500);
            }),
          ),
        ),
        messaging: FixturePushMessagingGateway(authorized: false),
      );

      final result = await gateway.syncRule(
        location: const AlertLocationInput(
          label: 'Paris, France',
          latitude: 48.8566,
          longitude: 2.3522,
          timeZone: 'Europe/Paris',
        ),
        leadMinutes: 15,
        minimumIntensity: RainAlertIntensity.moderate,
        quietHours: const AlertQuietHoursInput(
          enabled: false,
          start: '22:00',
          end: '07:00',
        ),
      );

      expect(result, RemoteRainAlertSyncResult.unavailable);
      expect(requests, 0);
    },
  );

  test('retains remote ownership after a temporary refresh failure', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'alerts.remote_active:v1': true,
    });
    final gateway = ChetiwaRemoteRainAlertGateway(
      api: ChetiwaAlertApi(
        ChetiwaApiClient(
          baseUri: Uri.parse('https://api.chetiwa.test/'),
          client: MockClient((request) async => http.Response('', 503)),
        ),
      ),
      messaging: FixturePushMessagingGateway(token: 'fcm-token'),
      phoneTimeZone: () async => 'Europe/Paris',
      appVersion: () async => '1.0.0+7',
      platform: () => 'android',
      locale: () => 'fr',
    );

    final result = await gateway.syncRule(
      location: const AlertLocationInput(
        label: 'Paris, France',
        latitude: 48.8566,
        longitude: 2.3522,
        timeZone: 'Europe/Paris',
      ),
      leadMinutes: 15,
      minimumIntensity: RainAlertIntensity.moderate,
      quietHours: const AlertQuietHoursInput(
        enabled: false,
        start: '22:00',
        end: '07:00',
      ),
    );

    expect(result, RemoteRainAlertSyncResult.retained);
  });
}

http.Response _response(Map<String, Object?> data, {int status = 200}) =>
    http.Response(
      jsonEncode(<String, Object?>{'data': data}),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _alertJson() => <String, Object?>{
  'id': '00000000000000000000000000000001',
  'location': <String, Object?>{
    'label': 'Paris, France',
    'latitude': 48.8566,
    'longitude': 2.3522,
    'timeZone': 'Europe/Paris',
  },
  'leadMinutes': 15,
  'minimumIntensity': 'moderate',
  'quietHours': <String, Object?>{
    'enabled': true,
    'start': '22:00',
    'end': '07:00',
  },
  'enabled': true,
  'createdAt': '2026-08-24T18:30:00.000Z',
  'updatedAt': '2026-08-24T18:30:00.000Z',
};
