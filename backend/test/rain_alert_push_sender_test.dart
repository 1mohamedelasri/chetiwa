import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:googleapis/fcm/v1.dart' as fcm;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sends HTTP v1 payload with TTL, collapse key and navigation data',
    () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/projects/chetiwa/messages:send');
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, String>{
            'name': 'projects/chetiwa/messages/message-1',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final sender = FirebaseRainAlertPushSender(
        api: fcm.FirebaseCloudMessagingApi(client),
        projectId: 'chetiwa',
        now: () => DateTime.utc(2026, 8, 24, 10),
      );
      final now = DateTime.utc(2026, 8, 24, 10);
      final outcome = await sender.send(
        PendingAlertDelivery(
          draft: AlertDeliveryDraft(
            eventId: 'event-1',
            ownerHash: 'owner-1',
            alertId: 'main',
            cellKey: '0.050:2777:3647',
            location: const AlertLocation(
              label: 'Paris, France',
              latitude: 48.8566,
              longitude: 2.3522,
              timeZone: 'Europe/Paris',
            ),
            intensity: AlertRainIntensity.moderate,
            expectedAt: now.add(const Duration(minutes: 10)),
            title: 'Pluie bientôt',
            body: 'Pluie modérée prévue à Paris',
            createdAt: now,
            expiresAt: now.add(const Duration(minutes: 30)),
          ),
          pushToken: 'push-token',
          platform: 'android',
          attempts: 0,
          nextAttemptAt: now,
        ),
      );

      expect(outcome, PushSendOutcome.sent);
      final message = payload['message'] as Map<String, dynamic>;
      expect(message['token'], 'push-token');
      expect((message['android'] as Map)['ttl'], '1800s');
      expect((message['android'] as Map)['collapseKey'], isNotEmpty);
      expect((message['data'] as Map)['eventId'], 'event-1');
      expect((message['data'] as Map)['section'], 'radar');
      expect(
        ((message['apns'] as Map)['headers'] as Map)['apns-expiration'],
        '${now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000}',
      );
    },
  );

  test('classifies UNREGISTERED as an invalid device token', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 404,
            'message': 'Requested entity was not found.',
            'status': 'NOT_FOUND',
            'details': <Object?>[
              <String, Object?>{
                '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
                'errorCode': 'UNREGISTERED',
              },
            ],
          },
        }),
        404,
        headers: const <String, String>{'content-type': 'application/json'},
      ),
    );
    final sender = FirebaseRainAlertPushSender(
      api: fcm.FirebaseCloudMessagingApi(client),
      projectId: 'chetiwa',
    );

    expect(
      await sender.send(_pendingDelivery(DateTime.utc(2026, 8, 24, 10))),
      PushSendOutcome.invalidToken,
    );
  });
}

PendingAlertDelivery _pendingDelivery(DateTime now) => PendingAlertDelivery(
  draft: AlertDeliveryDraft(
    eventId: 'event-invalid',
    ownerHash: 'owner-1',
    alertId: 'main',
    cellKey: 'cell-1',
    location: const AlertLocation(
      label: 'Paris, France',
      latitude: 48.8566,
      longitude: 2.3522,
      timeZone: 'Europe/Paris',
    ),
    intensity: AlertRainIntensity.moderate,
    expectedAt: now.add(const Duration(minutes: 10)),
    title: 'Pluie bientôt',
    body: 'Pluie modérée prévue à Paris',
    createdAt: now,
    expiresAt: now.add(const Duration(minutes: 30)),
  ),
  pushToken: 'invalid-token',
  platform: 'ios',
  attempts: 0,
  nextAttemptAt: now,
);
