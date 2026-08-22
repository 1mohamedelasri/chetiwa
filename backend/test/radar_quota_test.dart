import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  test('free quota blocks after the configured number of sessions', () {
    final tracker = RadarQuotaTracker(
      policy: const RadarQuotaPolicy(freeSessions: 2, premiumSessions: 5),
    );
    final now = DateTime.utc(2026, 8, 22);

    expect(
      tracker
          .evaluate(ownerKey: 'device', plan: RadarPlan.free, now: now)
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(ownerKey: 'device', plan: RadarPlan.free, now: now)
          .allowed,
      isTrue,
    );
    final blocked = tracker.evaluate(
      ownerKey: 'device',
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
          .evaluate(ownerKey: 'free', plan: RadarPlan.free, now: now)
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(
            ownerKey: 'free',
            plan: RadarPlan.free,
            now: now.add(const Duration(days: 1)),
          )
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(ownerKey: 'premium', plan: RadarPlan.premium, now: now)
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(ownerKey: 'premium', plan: RadarPlan.premium, now: now)
          .allowed,
      isTrue,
    );
    expect(
      tracker
          .evaluate(ownerKey: 'premium', plan: RadarPlan.premium, now: now)
          .allowed,
      isFalse,
    );
  });
}
