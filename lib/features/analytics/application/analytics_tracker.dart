import 'package:firebase_analytics/firebase_analytics.dart';

import 'analytics_consent_controller.dart';

typedef AnalyticsEventLogger =
    Future<void> Function(String name, {Map<String, Object>? parameters});

/// The complete Analytics allow-list for the local-first MVP.
///
/// Parameters deliberately exclude location labels, coordinates, search text,
/// weather values, device identifiers and any advertising identifier.
final class AnalyticsTracker {
  AnalyticsTracker({
    required AnalyticsConsentController consent,
    AnalyticsEventLogger? logEvent,
  }) : _consent = consent,
       _logEvent = logEvent ?? _logFirebaseEvent;

  final AnalyticsConsentController _consent;
  final AnalyticsEventLogger _logEvent;

  static Future<void> _logFirebaseEvent(
    String name, {
    Map<String, Object>? parameters,
  }) => FirebaseAnalytics.instance.logEvent(name: name, parameters: parameters);

  Future<void> tabSelected(String tab) =>
      _log('weather_tab_selected', parameters: {'tab': tab});

  Future<void> locationSearchRequested() => _log('location_search_requested');

  Future<void> locationSelected(String source) =>
      _log('location_selected', parameters: {'source': source});

  Future<void> alertPreferenceChanged(bool enabled) => _log(
    'rain_alert_preference_changed',
    parameters: {'enabled': enabled ? 'true' : 'false'},
  );

  /// Records operational degradation without any location, URL, provider
  /// payload, device identifier or weather value.
  Future<void> radarAvailabilityIssue({
    required String issue,
    required String surface,
    required bool cachedDataVisible,
  }) => _log(
    'radar_availability_issue',
    parameters: <String, Object>{
      'issue': issue,
      'surface': surface,
      'cached_data_visible': cachedDataVisible ? 'true' : 'false',
    },
  );

  Future<void> _log(String name, {Map<String, Object>? parameters}) async {
    if (!_consent.isEnabled) return;
    try {
      await _logEvent(name, parameters: parameters);
    } catch (_) {
      // Measurement must never affect a weather, search or alert interaction.
    }
  }
}
