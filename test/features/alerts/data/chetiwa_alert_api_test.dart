import 'dart:convert';

import 'package:chetiwa/core/network/chetiwa_api_client.dart';
import 'package:chetiwa/features/alerts/data/chetiwa_alert_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('registers device and sends the private installation header', () async {
    late http.Request captured;
    final api = ChetiwaAlertApi(
      ChetiwaApiClient(
        baseUri: Uri.parse('https://api.chetiwa.test/'),
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'device': <String, Object?>{'registered': true},
              },
            }),
            201,
          );
        }),
      ),
    );

    await api.registerDevice(
      platform: 'android',
      locale: 'fr',
      timeZone: 'Europe/Paris',
      notificationsEnabled: true,
      pushToken: 'push-token',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/devices');
    expect(captured.headers['x-chetiwa-device-id'], matches(r'^[a-f0-9]{32}$'));
    expect(jsonDecode(captured.body), containsPair('pushToken', 'push-token'));
  });

  test('parses alert CRUD responses into one stable model', () async {
    final requests = <http.Request>[];
    final api = ChetiwaAlertApi(
      ChetiwaApiClient(
        baseUri: Uri.parse('https://api.chetiwa.test/'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'DELETE') return http.Response('', 204);
          final alert = _alertJson(enabled: request.method != 'PATCH');
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': request.method == 'GET'
                  ? <String, Object?>{
                      'alerts': <Map<String, Object?>>[alert],
                    }
                  : <String, Object?>{'alert': alert},
            }),
            request.method == 'POST' ? 201 : 200,
          );
        }),
      ),
    );

    final input = RainAlertInput(
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
      enabled: true,
    );

    final created = await api.createAlert(input);
    final listed = await api.listAlerts();
    final updated = await api.updateAlert(created.id, enabled: false);
    await api.deleteAlert(created.id);

    expect(created.location.label, 'Paris, France');
    expect(created.minimumIntensity, RainAlertIntensity.moderate);
    expect(listed, hasLength(1));
    expect(updated.enabled, isFalse);
    expect(requests.map((request) => request.method), <String>[
      'POST',
      'GET',
      'PATCH',
      'DELETE',
    ]);
  });
}

Map<String, Object?> _alertJson({required bool enabled}) => <String, Object?>{
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
  'enabled': enabled,
  'createdAt': '2026-08-20T18:30:00.000Z',
  'updatedAt': '2026-08-20T18:30:00.000Z',
};
