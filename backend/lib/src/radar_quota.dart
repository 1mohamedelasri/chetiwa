import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import 'api_exception.dart';
import 'shared_counter.dart';

enum RadarPlan { free, premium }

final class RadarQuotaPolicy {
  const RadarQuotaPolicy({
    this.enabled = true,
    this.freeSessions = 20,
    this.premiumSessions = 200,
    this.window = const Duration(days: 30),
  }) : assert(freeSessions > 0),
       assert(premiumSessions > 0);

  final bool enabled;
  final int freeSessions;
  final int premiumSessions;
  final Duration window;

  int limitFor(RadarPlan plan) =>
      plan == RadarPlan.premium ? premiumSessions : freeSessions;
}

final class RadarQuotaDecision {
  const RadarQuotaDecision({
    required this.allowed,
    required this.limit,
    required this.used,
    required this.remaining,
    required this.resetAt,
  });

  final bool allowed;
  final int limit;
  final int used;
  final int remaining;
  final DateTime resetAt;
}

/// In-memory by design for the local/staging foundation. Production must use
/// a shared implementation before Cloud Run is scaled beyond one instance.
final class RadarQuotaTracker {
  RadarQuotaTracker({this.policy = const RadarQuotaPolicy()});

  final RadarQuotaPolicy policy;
  final Map<String, _RadarWindow> _windows = {};

  RadarQuotaDecision evaluate({
    required String ownerKey,
    required RadarPlan plan,
    required DateTime now,
  }) {
    final instant = now.toUtc();
    final current = _windows[ownerKey];
    final window = current == null || !instant.isBefore(current.resetAt)
        ? _RadarWindow(startedAt: instant, resetAt: instant.add(policy.window))
        : current;
    window.used++;
    _windows[ownerKey] = window;
    final limit = policy.limitFor(plan);
    final allowed = window.used <= limit;
    return RadarQuotaDecision(
      allowed: allowed,
      limit: limit,
      used: window.used,
      remaining: allowed ? limit - window.used : 0,
      resetAt: window.resetAt,
    );
  }

  void clear() => _windows.clear();
}

final class DistributedRadarQuotaGuard {
  const DistributedRadarQuotaGuard({
    required this.policy,
    required this.counter,
  });

  final RadarQuotaPolicy policy;
  final SharedCounter counter;

  Future<RadarQuotaDecision> evaluate({
    required String ownerKey,
    required RadarPlan plan,
    required DateTime now,
  }) async {
    final instant = now.toUtc();
    final month = '${instant.year}-${instant.month.toString().padLeft(2, '0')}';
    final key = 'radar-quota:$month:$plan:$ownerKey';
    final used = await counter.increment(key, ttl: policy.window);
    final limit = policy.limitFor(plan);
    final allowed = used <= limit;
    return RadarQuotaDecision(
      allowed: allowed,
      limit: limit,
      used: used,
      remaining: allowed ? limit - used : 0,
      resetAt: DateTime.utc(instant.year, instant.month + 1),
    );
  }
}

RadarPlan radarPlanFromRequest(Request request) {
  final value = request.headers['x-chetiwa-plan']?.trim().toLowerCase();
  return value == 'premium' || value == 'chetiwa+'
      ? RadarPlan.premium
      : RadarPlan.free;
}

String radarQuotaOwner(Request request) {
  final device = request.headers['x-chetiwa-device-id']?.trim();
  final source = device == null || device.isEmpty
      ? request.headers['x-forwarded-for']?.split(',').first.trim() ??
            request.headers['x-real-ip'] ??
            'anonymous'
      : device;
  return sha256.convert(utf8.encode(source)).toString();
}

ApiException radarQuotaExceeded(RadarQuotaDecision decision) => ApiException(
  statusCode: 429,
  code: 'radar_quota_exceeded',
  message:
      'Radar monthly quota reached; it resets at ${decision.resetAt.toIso8601String()}',
);

ApiException radarDisabled() => const ApiException(
  statusCode: 503,
  code: 'radar_disabled',
  message: 'Radar is temporarily unavailable',
);

final class _RadarWindow {
  _RadarWindow({required this.startedAt, required this.resetAt});

  final DateTime startedAt;
  final DateTime resetAt;
  int used = 0;
}
