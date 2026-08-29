import 'package:chetiwa/core/notifications/rain_alert_navigation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retains a valid cold-start rain alert until the screen consumes it',
    () {
      final controller = RainAlertNavigationController();
      final intent = RainAlertNavigationIntent.fromData(<String, dynamic>{
        'type': 'rain_alert',
        'eventId': 'event-1',
        'locationLabel': 'Paris, France',
        'latitude': '48.8566',
        'longitude': '2.3522',
        'section': 'radar',
      });

      expect(intent, isNotNull);
      controller.open(intent!);
      expect(controller.take()?.locationLabel, 'Paris, France');
      expect(controller.take(), isNull);
      controller.dispose();
    },
  );

  test('rejects malformed or unrelated notification payloads', () {
    expect(
      RainAlertNavigationIntent.fromData(<String, dynamic>{
        'type': 'marketing',
      }),
      isNull,
    );
    expect(
      RainAlertNavigationIntent.fromData(<String, dynamic>{
        'type': 'rain_alert',
        'eventId': 'event-1',
        'locationLabel': 'Invalid',
        'latitude': '999',
        'longitude': '2',
      }),
      isNull,
    );
  });

  test('accepts only allow-listed official vigilance destinations', () {
    final controller = RainAlertNavigationController();
    final intent = OfficialAlertNavigationIntent.fromData(<String, dynamic>{
      'type': 'official_weather_alert',
      'source': 'meteofrance',
      'eventId': 'official-1',
      'departmentCode': '75',
      'officialUrl': 'https://vigilance.meteofrance.fr/fr',
    });

    expect(intent, isNotNull);
    controller.openOfficial(intent!);
    expect(controller.takeOfficial()?.departmentCode, '75');
    expect(
      OfficialAlertNavigationIntent.fromData(<String, dynamic>{
        'type': 'official_weather_alert',
        'source': 'meteoalarm',
        'eventId': 'official-eu-1',
        'departmentCode': 'EU',
        'officialUrl': 'https://www.meteoalarm.org',
      }),
      isNotNull,
    );
    expect(
      OfficialAlertNavigationIntent.fromData(<String, dynamic>{
        'type': 'official_weather_alert',
        'source': 'meteofrance',
        'eventId': 'official-2',
        'departmentCode': '75',
        'officialUrl': 'https://example.com/phishing',
      }),
      isNull,
    );
    controller.dispose();
  });
}
