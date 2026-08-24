import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const fallback = RainAlertRuntimeControl(
    engineEnabled: true,
    sendEnabled: true,
    observedCostCents: 0,
    softBudgetCents: 2500,
    hardBudgetCents: 5000,
  );

  test('decodes the official Cloud Billing Pub/Sub envelope', () {
    final update = BillingBudgetUpdate.parsePubSubEnvelope(
      _envelope(cost: 25.125),
      expectedCurrency: 'EUR',
    );

    expect(update.costCents, 2513);
    expect(update.costIntervalStart, DateTime.utc(2026, 8));
  });

  test('rejects a budget expressed in another currency', () {
    expect(
      () => BillingBudgetUpdate.parsePubSubEnvelope(
        _envelope(cost: 25, currency: 'USD'),
        expectedCurrency: 'EUR',
      ),
      throwsFormatException,
    );
  });

  test(
    'updates the cost control without logging or returning payload data',
    () async {
      final store = _MemoryOperationsStore(fallback);
      final handler = createRainAlertBudgetGuard(
        store: store,
        fallbackControl: fallback,
        expectedCurrency: 'EUR',
      );
      final response = await handler(
        Request(
          'POST',
          Uri.parse('https://guard.test/'),
          body: jsonEncode(_envelope(cost: 51)),
        ),
      );

      expect(response.statusCode, 204);
      expect(store.control.observedCostCents, 5100);
      expect(store.control.mayEvaluate, isFalse);
    },
  );
}

Map<String, Object?> _envelope({
  required double cost,
  String currency = 'EUR',
}) {
  final payload = <String, Object?>{
    'budgetDisplayName': 'Chetiwa alerts',
    'costAmount': cost,
    'costIntervalStart': '2026-08-01T00:00:00Z',
    'budgetAmount': 50,
    'budgetAmountType': 'SPECIFIED_AMOUNT',
    'currencyCode': currency,
  };
  return <String, Object?>{
    'message': <String, Object?>{
      'attributes': <String, Object?>{'schemaVersion': '1.0'},
      'data': base64.encode(utf8.encode(jsonEncode(payload))),
    },
  };
}

final class _MemoryOperationsStore implements RainAlertOperationsStore {
  _MemoryOperationsStore(this.control);

  RainAlertRuntimeControl control;

  @override
  Future<RainAlertRuntimeControl> loadRuntimeControl(
    RainAlertRuntimeControl fallback,
  ) async => control;

  @override
  Future<void> recordRunMetric(RainAlertRunMetric metric) async {}

  @override
  Future<RainAlertRuntimeControl> updateObservedCost({
    required int observedCostCents,
    required DateTime costIntervalStart,
    required RainAlertRuntimeControl fallback,
  }) async {
    final hard = observedCostCents >= control.hardBudgetCents;
    control = RainAlertRuntimeControl(
      engineEnabled: hard ? false : control.engineEnabled,
      sendEnabled: hard ? false : control.sendEnabled,
      observedCostCents: observedCostCents,
      softBudgetCents: control.softBudgetCents,
      hardBudgetCents: control.hardBudgetCents,
      costIntervalStart: costIntervalStart,
    );
    return control;
  }
}
