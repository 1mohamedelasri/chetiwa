import 'package:chetiwa/features/analytics/application/analytics_consent_controller.dart';
import 'package:chetiwa/features/analytics/application/analytics_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not log anything before analytics consent', () async {
    final events = <String>[];
    final tracker = AnalyticsTracker(
      consent: AnalyticsConsentController(
        initiallyEnabled: false,
        updateCollection: (_) async {},
      ),
      logEvent: (name, {parameters}) async => events.add(name),
    );

    await tracker.locationSearchRequested();
    await tracker.tabSelected('radar');

    expect(events, isEmpty);
  });

  test('uses the MVP allow-list without precise location data', () async {
    final events = <({String name, Map<String, Object>? parameters})>[];
    final tracker = AnalyticsTracker(
      consent: AnalyticsConsentController(
        initiallyEnabled: true,
        updateCollection: (_) async {},
      ),
      logEvent: (name, {parameters}) async =>
          events.add((name: name, parameters: parameters)),
    );

    await tracker.tabSelected('radar');
    await tracker.locationSearchRequested();
    await tracker.locationSelected('precise');
    await tracker.alertPreferenceChanged(true);
    await tracker.radarAvailabilityIssue(
      issue: 'providerUnavailable',
      surface: 'metadata',
      cachedDataVisible: true,
    );

    expect(events.map((event) => event.name), [
      'weather_tab_selected',
      'location_search_requested',
      'location_selected',
      'rain_alert_preference_changed',
      'radar_availability_issue',
    ]);
    expect(events[0].parameters, <String, Object>{'tab': 'radar'});
    expect(events[1].parameters, isNull);
    expect(events[2].parameters, <String, Object>{'source': 'precise'});
    expect(events[3].parameters, <String, Object>{'enabled': 'true'});
    expect(events[4].parameters, <String, Object>{
      'issue': 'providerUnavailable',
      'surface': 'metadata',
      'cached_data_visible': 'true',
    });
    expect(
      events.expand((event) => event.parameters?.keys ?? const <String>[]),
      isNot(contains(anyOf('latitude', 'longitude', 'location', 'url'))),
    );
  });
}
