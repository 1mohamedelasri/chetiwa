import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:googleapis/fcm/v1.dart' as fcm;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'sends an official, collapsible and time-sensitive FCM payload',
    () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, String>{
            'name': 'projects/chetiwa/messages/vigilance-1',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final now = DateTime.utc(2026, 8, 29, 12);
      final sender = FirebaseVigilancePushSender(
        api: fcm.FirebaseCloudMessagingApi(client),
        projectId: 'chetiwa',
        now: () => now,
      );
      final outcome = await sender.send(
        PendingVigilanceDelivery(
          draft: VigilanceDeliveryDraft(
            eventId: 'official-1',
            ownerHash: 'owner',
            alertId: 'alert',
            departmentCode: '75',
            departmentName: 'Paris',
            phenomenon: VigilancePhenomenon.thunderstorms,
            kind: VigilanceDeliveryKind.started,
            level: VigilanceLevel.orange,
            beginsAt: now,
            endsAt: now.add(const Duration(hours: 6)),
            title: 'Vigilance orange · Paris',
            body: 'Orages. Consultez les consignes officielles.',
            createdAt: now,
            expiresAt: now.add(const Duration(hours: 6)),
            settingsFingerprint: 'settings-fingerprint',
          ),
          pushToken: 'push-token',
          platform: 'ios',
          attempts: 0,
          nextAttemptAt: now,
        ),
      );

      expect(outcome, VigilancePushOutcome.sent);
      final message = payload['message'] as Map<String, dynamic>;
      final data = message['data'] as Map<String, dynamic>;
      final android = message['android'] as Map<String, dynamic>;
      final apns = message['apns'] as Map<String, dynamic>;
      expect(data['type'], 'official_weather_alert');
      expect(data['source'], 'meteofrance');
      expect(data['officialUrl'], 'https://vigilance.meteofrance.fr/fr');
      expect(android['collapseKey'], 'vigilance-75-3');
      expect(
        (android['notification'] as Map)['channelId'],
        'official_weather_alerts',
      );
      expect(
        (((apns['payload'] as Map)['aps'] as Map)['interruption-level']),
        'time-sensitive',
      );
    },
  );
}
