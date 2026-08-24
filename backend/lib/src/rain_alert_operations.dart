final class RainAlertRuntimeControl {
  const RainAlertRuntimeControl({
    required this.engineEnabled,
    required this.sendEnabled,
    required this.observedCostCents,
    required this.softBudgetCents,
    required this.hardBudgetCents,
    this.costIntervalStart,
    this.updatedAt,
  });

  final bool engineEnabled;
  final bool sendEnabled;
  final int observedCostCents;
  final int softBudgetCents;
  final int hardBudgetCents;
  final DateTime? costIntervalStart;
  final DateTime? updatedAt;

  bool get softBudgetExceeded => observedCostCents >= softBudgetCents;
  bool get hardBudgetExceeded => observedCostCents >= hardBudgetCents;
  bool get mayEvaluate => engineEnabled && !hardBudgetExceeded;
  bool get maySend => mayEvaluate && sendEnabled;
}

final class RainAlertRunMetric {
  const RainAlertRunMetric({
    required this.runId,
    required this.startedAt,
    required this.durationMilliseconds,
    required this.mode,
    required this.status,
    required this.activeAlerts,
    required this.cellsEvaluated,
    required this.providerFailures,
    required this.alertsEvaluated,
    required this.deliveriesProposed,
    required this.deliveriesEnqueued,
    required this.pushPending,
    required this.pushSent,
    required this.pushRetried,
    required this.pushFailed,
    required this.invalidTokens,
  });

  final String runId;
  final DateTime startedAt;
  final int durationMilliseconds;
  final String mode;
  final String status;
  final int activeAlerts;
  final int cellsEvaluated;
  final int providerFailures;
  final int alertsEvaluated;
  final int deliveriesProposed;
  final int deliveriesEnqueued;
  final int pushPending;
  final int pushSent;
  final int pushRetried;
  final int pushFailed;
  final int invalidTokens;
}

abstract interface class RainAlertOperationsStore {
  Future<RainAlertRuntimeControl> loadRuntimeControl(
    RainAlertRuntimeControl fallback,
  );

  Future<void> recordRunMetric(RainAlertRunMetric metric);

  /// Stores the latest billing estimate and applies the hard cutoff.
  Future<RainAlertRuntimeControl> updateObservedCost({
    required int observedCostCents,
    required DateTime costIntervalStart,
    required RainAlertRuntimeControl fallback,
  });
}
