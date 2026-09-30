import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:chetiwa_backend/src/api_exception.dart';
import 'package:test/test.dart';

void main() {
  test('free quota blocks after the configured number of sessions', () {
    final tracker = RadarQuotaTracker(
      policy: const RadarQuotaPolicy(freeSessions: 2, premiumSessions: 5),
    );
    final now = DateTime.utc(2026, 8, 22);

    expect(
      tracker
          .evaluate(
            ownerKey: 'device',
            sessionId: 'session-00000001',
            plan: RadarPlan.free,
            now: now,
          )
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(
            ownerKey: 'device',
            sessionId: 'session-00000002',
            plan: RadarPlan.free,
            now: now,
          )
          .allowed,
      isTrue,
    );
    final blocked = tracker.evaluate(
      ownerKey: 'device',
      sessionId: 'session-00000003',
      plan: RadarPlan.free,
      now: now,
    );
    expect(blocked.allowed, isFalse);
    expect(blocked.remaining, 0);
  });

  test('quota resets after its window and premium has its own limit', () {
    final tracker = RadarQuotaTracker(
      policy: const RadarQuotaPolicy(
        freeSessions: 1,
        premiumSessions: 2,
        window: Duration(days: 1),
      ),
    );
    final now = DateTime.utc(2026, 8, 22);
    expect(
      tracker
          .evaluate(
            ownerKey: 'free',
            sessionId: 'session-free-0001',
            plan: RadarPlan.free,
            now: now,
          )
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(
            ownerKey: 'free',
            sessionId: 'session-free-0002',
            plan: RadarPlan.free,
            now: now.add(const Duration(days: 1)),
          )
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(
            ownerKey: 'premium',
            sessionId: 'session-premium-0001',
            plan: RadarPlan.premium,
            now: now,
          )
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(
            ownerKey: 'premium',
            sessionId: 'session-premium-0002',
            plan: RadarPlan.premium,
            now: now,
          )
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(
            ownerKey: 'premium',
            sessionId: 'session-premium-0003',
            plan: RadarPlan.premium,
            now: now,
          )
          .allowed,
      isFalse,
    );
  });

  test('retries with the same session id are counted once', () {
    final tracker = RadarQuotaTracker(
      policy: const RadarQuotaPolicy(freeSessions: 2, premiumSessions: 5),
    );
    final now = DateTime.utc(2026, 8, 22);

    final first = tracker.evaluate(
      ownerKey: 'device',
      sessionId: 'session-idempotent-01',
      plan: RadarPlan.free,
      now: now,
    );
    final retry = tracker.evaluate(
      ownerKey: 'device',
      sessionId: 'session-idempotent-01',
      plan: RadarPlan.free,
      now: now,
    );

    expect(first.used, 1);
    expect(retry.used, 1);
    expect(retry.remaining, 1);
  });

  test('distributed quota also deduplicates session retries', () async {
    final guard = DistributedRadarQuotaGuard(
      policy: const RadarQuotaPolicy(freeSessions: 2, premiumSessions: 5),
      counter: InMemorySharedCounter(),
    );
    final now = DateTime.utc(2026, 8, 22);

    final first = await guard.evaluate(
      ownerKey: 'device',
      sessionId: 'distributed-session-01',
      plan: RadarPlan.free,
      now: now,
    );
    final retry = await guard.evaluate(
      ownerKey: 'device',
      sessionId: 'distributed-session-01',
      plan: RadarPlan.free,
      now: now,
    );

    expect(first.used, 1);
    expect(retry.used, 1);
    expect(retry.remaining, 1);
  });

  test(
    'unknown owners fail closed at capacity without resetting live quotas',
    () {
      final tracker = RadarQuotaTracker(
        maximumOwners: 1,
        policy: const RadarQuotaPolicy(freeSessions: 1),
      );
      final now = DateTime.utc(2026, 9, 19);
      tracker.evaluate(
        ownerKey: 'existing',
        sessionId: 'one',
        plan: RadarPlan.free,
        now: now,
      );
      expect(
        () => tracker.evaluate(
          ownerKey: 'new',
          sessionId: 'one',
          plan: RadarPlan.free,
          now: now,
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'radar_quota_capacity',
          ),
        ),
      );
      expect(
        tracker
            .evaluate(
              ownerKey: 'existing',
              sessionId: 'two',
              plan: RadarPlan.free,
              now: now,
            )
            .allowed,
        isFalse,
      );
      expect(
        tracker
            .evaluate(
              ownerKey: 'new',
              sessionId: 'one',
              plan: RadarPlan.free,
              now: now.add(const Duration(days: 30)),
            )
            .allowed,
        isTrue,
      );
    },
  );

  test('unlimited distinct session IDs saturate above the largest plan', () {
    final tracker = RadarQuotaTracker(
      policy: const RadarQuotaPolicy(freeSessions: 2, premiumSessions: 5),
    );
    final now = DateTime.utc(2026, 9, 19);
    for (var index = 0; index < 10000; index++) {
      final result = tracker.evaluate(
        ownerKey: 'existing',
        sessionId: 'session-$index',
        plan: RadarPlan.free,
        now: now,
      );
      expect(result.used, lessThanOrEqualTo(6));
    }
    final upgraded = tracker.evaluate(
      ownerKey: 'existing',
      sessionId: 'upgrade',
      plan: RadarPlan.premium,
      now: now,
    );
    expect(upgraded.allowed, isFalse);
    expect(upgraded.used, 6);
  });
}
