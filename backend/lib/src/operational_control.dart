import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'shared_counter.dart';

final class OperationalSnapshot {
  const OperationalSnapshot({
    required this.requests,
    required this.errors,
    required this.cacheHits,
    required this.cacheMisses,
    required this.totalLatencyMs,
    required this.totalFreshnessMs,
    required this.tileBytes,
    required this.tileRequests,
    required this.budgetAlerts,
  });

  final int requests;
  final int errors;
  final int cacheHits;
  final int cacheMisses;
  final int totalLatencyMs;
  final int totalFreshnessMs;
  final int tileBytes;
  final int tileRequests;
  final Map<int, int> budgetAlerts;

  double get averageLatencyMs => requests == 0 ? 0 : totalLatencyMs / requests;
  double get errorRate => requests == 0 ? 0 : errors / requests;
  double get cacheHitRate =>
      cacheHits + cacheMisses == 0 ? 0 : cacheHits / (cacheHits + cacheMisses);

  Map<String, Object> toJson() => <String, Object>{
    'requests': requests,
    'errors': errors,
    'cacheHits': cacheHits,
    'cacheMisses': cacheMisses,
    'averageLatencyMs': averageLatencyMs,
    'averageFreshnessMs': requests == 0 ? 0 : totalFreshnessMs / requests,
    'tileBytes': tileBytes,
    'tileRequests': tileRequests,
    'budgetAlerts': budgetAlerts.map((key, value) => MapEntry('$key', value)),
    'cacheHitRate': cacheHitRate,
    'errorRate': errorRate,
  };
}

final class OperationalMetrics {
  int _requests = 0;
  int _errors = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalLatencyMs = 0;
  int _totalFreshnessMs = 0;
  int _tileBytes = 0;
  int _tileRequests = 0;
  final Map<int, int> _budgetAlerts = <int, int>{};

  void recordBudgetAlert(int threshold) {
    _budgetAlerts[threshold] = (_budgetAlerts[threshold] ?? 0) + 1;
  }

  void record({
    required Duration latency,
    required Duration freshness,
    required bool error,
    required String cacheStatus,
    int tileBytes = 0,
  }) {
    _requests++;
    if (error) _errors++;
    if (cacheStatus == 'HIT') _cacheHits++;
    if (cacheStatus == 'MISS' || cacheStatus == 'STALE') _cacheMisses++;
    _totalLatencyMs += latency.inMilliseconds;
    _totalFreshnessMs += freshness.inMilliseconds;
    if (tileBytes > 0) {
      _tileBytes += tileBytes;
      _tileRequests++;
    }
  }

  OperationalSnapshot snapshot() => OperationalSnapshot(
    requests: _requests,
    errors: _errors,
    cacheHits: _cacheHits,
    cacheMisses: _cacheMisses,
    totalLatencyMs: _totalLatencyMs,
    totalFreshnessMs: _totalFreshnessMs,
    tileBytes: _tileBytes,
    tileRequests: _tileRequests,
    budgetAlerts: Map<int, int>.unmodifiable(_budgetAlerts),
  );
}

final class BudgetDecision {
  const BudgetDecision({
    required this.allowed,
    required this.spentCents,
    required this.limitCents,
    required this.threshold,
    required this.killSwitch,
  });

  final bool allowed;
  final int spentCents;
  final int limitCents;
  final int? threshold;
  final bool killSwitch;
}

final class MonthlyBudgetController {
  MonthlyBudgetController({required this.limitCents, this.killAtLimit = true})
    : assert(limitCents > 0);

  final int limitCents;
  final bool killAtLimit;
  int _spentCents = 0;
  String _period = _monthKey(DateTime.timestamp());
  final Set<int> _alerted = <int>{};

  BudgetDecision record(int costCents, {DateTime? now}) {
    final currentPeriod = _monthKey(now ?? DateTime.timestamp());
    if (currentPeriod != _period) {
      _period = currentPeriod;
      _spentCents = 0;
      _alerted.clear();
    }
    _spentCents += costCents.clamp(0, 1 << 30);
    int? threshold;
    for (final percent in const [50, 75, 90]) {
      if (_spentCents * 100 >= limitCents * percent && _alerted.add(percent)) {
        threshold = percent;
        break;
      }
    }
    final killed = killAtLimit && _spentCents >= limitCents;
    return BudgetDecision(
      allowed: !killed,
      spentCents: _spentCents,
      limitCents: limitCents,
      threshold: threshold,
      killSwitch: killed,
    );
  }

  int get spentCents => _spentCents;

  static String _monthKey(DateTime value) =>
      '${value.toUtc().year}-${value.toUtc().month.toString().padLeft(2, '0')}';
}

final class DistributedBudgetController {
  DistributedBudgetController({
    required this.limitCents,
    required this.counter,
    this.killAtLimit = true,
  }) : assert(limitCents > 0);

  final int limitCents;
  final SharedCounter counter;
  final bool killAtLimit;
  final Set<int> _alerted = <int>{};

  Future<BudgetDecision> record(int costCents, {DateTime? now}) async {
    final instant = (now ?? DateTime.timestamp()).toUtc();
    final month = '${instant.year}-${instant.month.toString().padLeft(2, '0')}';
    final spent = await counter.increment(
      'radar-budget:$month',
      ttl: const Duration(days: 35),
      amount: costCents,
    );
    int? threshold;
    for (final percent in const [50, 75, 90]) {
      if (spent * 100 >= limitCents * percent && _alerted.add(percent)) {
        threshold = percent;
        break;
      }
    }
    return BudgetDecision(
      allowed: !killAtLimit || spent < limitCents,
      spentCents: spent,
      limitCents: limitCents,
      threshold: threshold,
      killSwitch: killAtLimit && spent >= limitCents,
    );
  }
}

Middleware operationalMetricsMiddleware(OperationalMetrics metrics) =>
    (Handler inner) => (Request request) async {
      final started = DateTime.timestamp();
      try {
        final response = await inner(request);
        final tileBytes =
            int.tryParse(response.headers['x-chetiwa-tile-bytes'] ?? '') ?? 0;
        metrics.record(
          latency: DateTime.timestamp().difference(started),
          freshness: Duration.zero,
          error: response.statusCode >= 500,
          cacheStatus: response.headers['x-cache'] ?? 'BYPASS',
          tileBytes: tileBytes,
        );
        if (tileBytes == 0) return response;
        final headers = Map<String, String>.of(response.headers)
          ..remove('x-chetiwa-tile-bytes');
        return response.change(headers: headers);
      } on Object {
        metrics.record(
          latency: DateTime.timestamp().difference(started),
          freshness: Duration.zero,
          error: true,
          cacheStatus: 'ERROR',
        );
        rethrow;
      }
    };

Response metricsResponse(OperationalMetrics metrics) => Response.ok(
  jsonEncode(<String, Object?>{'metrics': metrics.snapshot().toJson()}),
  headers: const {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);
