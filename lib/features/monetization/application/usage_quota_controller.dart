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

final class RadarSessionDecision {
  const RadarSessionDecision({
    required this.allowed,
    required this.enforced,
    required this.used,
    required this.limit,
    required this.resetAt,
  });

  final bool allowed;
  final bool enforced;
  final int used;
  final int limit;
  final DateTime resetAt;
}

abstract interface class RadarSessionGateway {
  Future<RadarSessionDecision> open({required bool premium});
}

final class UsageQuotaController extends ChangeNotifier {
  UsageQuotaController({
    required EntitlementController entitlement,
    bool persist = true,
    RadarSessionGateway? radarSessionGateway,
  }) : _entitlement = entitlement,
       _persist = persist,
       _radarSessionGateway = radarSessionGateway {
    _entitlement.addListener(_entitlementChanged);
    if (persist) unawaited(_restore());
  }

  static const _usedKey = 'monetization:radar_sessions_used:v1';
  static const _monthKey = 'monetization:radar_sessions_month:v1';
  final EntitlementController _entitlement;
  final bool _persist;
  final RadarSessionGateway? _radarSessionGateway;
  int _used = 0;
  String _month = _monthId(DateTime.now());
  int? _serverLimit;
  DateTime? _serverResetAt;
  var _serverEnforced = false;
  Future<bool>? _openingRadarSession;

  PremiumLimits get limits => PremiumLimits.forEntitlement(_entitlement);
  UsageQuotaSnapshot get radarSessions {
    _rolloverIfNeeded();
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    return UsageQuotaSnapshot(
      used: _used,
      limit: _serverLimit ?? limits.monthlyRadarSessions,
      resetAt: _serverResetAt ?? nextMonth,
    );
  }

  /// Launch policy: Radar is a core feature and local storage is never an
  /// authority for access control. Only a validated, explicitly enforced
  /// server decision may deny an opening.
  bool get canOpenRadar => !_serverEnforced || radarSessions.remaining > 0;

  Future<bool> consumeRadarSession() async {
    _used++;
    notifyListeners();
    await _persistValue();
    return true;
  }

  /// Records exactly one user-visible Radar opening. Backend/network failures
  /// never remove weather data; only an explicit enforced server decision can
  /// deny access.
  Future<bool> openRadarSession() {
    final inFlight = _openingRadarSession;
    if (inFlight != null) return inFlight;
    final operation = _openRadarSession();
    _openingRadarSession = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_openingRadarSession, operation)) {
          _openingRadarSession = null;
        }
      }),
    );
    return operation;
  }

  Future<bool> _openRadarSession() async {
    final gateway = _radarSessionGateway;
    if (gateway == null) return consumeRadarSession();
    try {
      final decision = await gateway.open(premium: _entitlement.isPremium);
      _used = decision.used;
      _serverLimit = decision.limit;
      _serverResetAt = decision.resetAt;
      _serverEnforced = decision.enforced;
      notifyListeners();
      await _persistValue();
      return !decision.enforced || decision.allowed;
    } on Object {
      return true;
    }
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
    _serverLimit = null;
    _serverResetAt = null;
    _serverEnforced = false;
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
