import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/chetiwa_alert_api.dart';

final class AlertPreferencesController extends ChangeNotifier {
  AlertPreferencesController({bool persist = true}) : _persist = persist {
    if (persist) unawaited(_restore());
  }

  static const _enabledKey = 'alerts.enabled';
  static const _leadMinutesKey = 'alerts.lead_minutes';
  static const _minimumIntensityKey = 'alerts.minimum_intensity';
  static const _quietHoursEnabledKey = 'alerts.quiet_hours_enabled';
  static const _quietHoursStartKey = 'alerts.quiet_hours_start';
  static const _quietHoursEndKey = 'alerts.quiet_hours_end';

  final bool _persist;
  bool _enabled = false;
  int _leadMinutes = 15;
  RainAlertIntensity _minimumIntensity = RainAlertIntensity.moderate;
  bool _quietHoursEnabled = false;
  String _quietHoursStart = '22:00';
  String _quietHoursEnd = '07:00';

  bool get enabled => _enabled;
  int get leadMinutes => _leadMinutes;
  RainAlertIntensity get minimumIntensity => _minimumIntensity;
  bool get quietHoursEnabled => _quietHoursEnabled;
  String get quietHoursStart => _quietHoursStart;
  String get quietHoursEnd => _quietHoursEnd;

  Future<void> setEnabled(bool value) => _update(enabled: value);
  Future<void> setLeadMinutes(int value) => _update(leadMinutes: value);
  Future<void> setMinimumIntensity(RainAlertIntensity value) =>
      _update(minimumIntensity: value);
  Future<void> setQuietHoursEnabled(bool value) =>
      _update(quietHoursEnabled: value);
  Future<void> setQuietHours({required String start, required String end}) =>
      _update(quietHoursStart: start, quietHoursEnd: end);

  Future<void> clear() async {
    _enabled = false;
    _leadMinutes = 15;
    _minimumIntensity = RainAlertIntensity.moderate;
    _quietHoursEnabled = false;
    _quietHoursStart = '22:00';
    _quietHoursEnd = '07:00';
    notifyListeners();
    if (!_persist) return;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_enabledKey),
      preferences.remove(_leadMinutesKey),
      preferences.remove(_minimumIntensityKey),
      preferences.remove(_quietHoursEnabledKey),
      preferences.remove(_quietHoursStartKey),
      preferences.remove(_quietHoursEndKey),
    ]);
  }

  Future<void> _update({
    bool? enabled,
    int? leadMinutes,
    RainAlertIntensity? minimumIntensity,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
  }) async {
    _enabled = enabled ?? _enabled;
    _leadMinutes = leadMinutes ?? _leadMinutes;
    _minimumIntensity = minimumIntensity ?? _minimumIntensity;
    _quietHoursEnabled = quietHoursEnabled ?? _quietHoursEnabled;
    _quietHoursStart = quietHoursStart ?? _quietHoursStart;
    _quietHoursEnd = quietHoursEnd ?? _quietHoursEnd;
    notifyListeners();
    if (!_persist) return;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      preferences.setBool(_enabledKey, _enabled),
      preferences.setInt(_leadMinutesKey, _leadMinutes),
      preferences.setString(_minimumIntensityKey, _minimumIntensity.name),
      preferences.setBool(_quietHoursEnabledKey, _quietHoursEnabled),
      preferences.setString(_quietHoursStartKey, _quietHoursStart),
      preferences.setString(_quietHoursEndKey, _quietHoursEnd),
    ]);
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    _enabled = preferences.getBool(_enabledKey) ?? false;
    _leadMinutes = preferences.getInt(_leadMinutesKey) ?? 15;
    _minimumIntensity = RainAlertIntensity.values.firstWhere(
      (value) => value.name == preferences.getString(_minimumIntensityKey),
      orElse: () => RainAlertIntensity.moderate,
    );
    _quietHoursEnabled = preferences.getBool(_quietHoursEnabledKey) ?? false;
    _quietHoursStart = preferences.getString(_quietHoursStartKey) ?? '22:00';
    _quietHoursEnd = preferences.getString(_quietHoursEndKey) ?? '07:00';
    notifyListeners();
  }
}
