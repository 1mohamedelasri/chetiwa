import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  test('budget emits 50/75/90 alerts and kills at the limit', () {
    final budget = MonthlyBudgetController(limitCents: 100);
    expect(budget.record(50).threshold, 50);
    expect(budget.record(25).threshold, 75);
    expect(budget.record(15).threshold, 90);
    expect(budget.record(10).allowed, isFalse);
  });

  test('budget resets at the start of a new month', () {
    final budget = MonthlyBudgetController(limitCents: 100);
    final august = DateTime.utc(2026, 8, 31);
    expect(budget.record(100, now: august).allowed, isFalse);
    expect(budget.record(1, now: DateTime.utc(2026, 9, 1)).allowed, isTrue);
  });

  test('in-memory shared counter honors increments and TTL windows', () async {
    final counter = InMemorySharedCounter();
    expect(await counter.increment('key', ttl: const Duration(minutes: 1)), 1);
    expect(await counter.increment('key', ttl: const Duration(minutes: 1)), 2);
  });
}
