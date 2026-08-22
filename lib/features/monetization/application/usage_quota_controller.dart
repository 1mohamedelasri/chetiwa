import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/premium_entitlement.dart';
import '../domain/premium_limits.dart';

final class UsageQuotaSnapshot {
  const UsageQuotaSnapshot({
    required this.used,
    required this.limit,
    required this.resetAt,
  });

  final int used;
  final int limit;
  final DateTime resetAt;
  int get remaining => (limit - used).clamp(0, limit);
}

final class UsageQuotaController extends ChangeNotifier {
  UsageQuotaController({
    required EntitlementController entitlement,
    bool persist = true,
  }) : _entitlement = entitlement,
       _persist = persist {
    _entitlement.addListener(_entitlementChanged);
    if (persist) unawaited(_restore());
  }

  static const _usedKey = 'monetization:radar_sessions_used:v1';
  static const _monthKey = 'monetization:radar_sessions_month:v1';
  final EntitlementController _entitlement;
  final bool _persist;
  int _used = 0;
  String _month = _monthId(DateTime.now());

  PremiumLimits get limits => PremiumLimits.forEntitlement(_entitlement);
  UsageQuotaSnapshot get radarSessions {
    _rolloverIfNeeded();
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    return UsageQuotaSnapshot(
      used: _used,
      limit: limits.monthlyRadarSessions,
      resetAt: nextMonth,
    );
  }

  bool get canOpenRadar => radarSessions.remaining > 0;

  Future<bool> consumeRadarSession() async {
    if (!canOpenRadar) return false;
    _used++;
    notifyListeners();
    await _persistValue();
    return true;
  }

  void _entitlementChanged() => notifyListeners();

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    _month = preferences.getString(_monthKey) ?? _month;
    _used = preferences.getInt(_usedKey) ?? 0;
    _rolloverIfNeeded();
    notifyListeners();
  }

  void _rolloverIfNeeded() {
    final month = _monthId(DateTime.now());
    if (_month == month) return;
    _month = month;
    _used = 0;
    unawaited(_persistValue());
  }

  Future<void> _persistValue() async {
    if (!_persist) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_monthKey, _month);
    await preferences.setInt(_usedKey, _used);
  }

  static String _monthId(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _entitlement.removeListener(_entitlementChanged);
    super.dispose();
  }
}
