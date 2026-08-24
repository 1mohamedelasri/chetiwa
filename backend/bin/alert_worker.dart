import 'dart:convert';
import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as time_zone;

Future<void> main() async {
  final config = RuntimeConfig.fromEnvironment();
  if (!config.rainAlertsEnabled || config.globalKillSwitch) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'disabled',
        'rainAlertsEnabled': config.rainAlertsEnabled,
        'globalKillSwitch': config.globalKillSwitch,
      }),
    );
    return;
  }
  if (config.environment == AppEnvironment.local ||
      config.googleCloudProject == null) {
    throw StateError(
      'alert_worker requires staging/production and GOOGLE_CLOUD_PROJECT',
    );
  }

  time_zone_data.initializeTimeZones();
  final store = await FirestoreDeviceAlertStore.connect(
    projectId: config.googleCloudProject!,
    databaseId: config.firestoreDatabaseId,
  );
  FirebaseRainAlertPushSender? sender;
  final startedAt = DateTime.now().toUtc();
  final stopwatch = Stopwatch()..start();
  try {
    final fallbackControl = RainAlertRuntimeControl(
      engineEnabled: config.rainAlertsEnabled,
      sendEnabled: config.rainAlertsSendEnabled,
      observedCostCents: 0,
      softBudgetCents: config.rainAlertSoftBudgetCents,
      hardBudgetCents: config.rainAlertHardBudgetCents,
    );
    final control = await store.loadRuntimeControl(fallbackControl);
    if (!control.mayEvaluate) {
      final status = control.hardBudgetExceeded
          ? 'budget_cutoff'
          : 'remote_disabled';
      final runId = 'control-${startedAt.millisecondsSinceEpoch}';
      stopwatch.stop();
      await store.recordRunMetric(
        RainAlertRunMetric(
          runId: runId,
          startedAt: startedAt,
          durationMilliseconds: stopwatch.elapsedMilliseconds,
          mode: 'disabled',
          status: status,
          activeAlerts: 0,
          cellsEvaluated: 0,
          providerFailures: 0,
          alertsEvaluated: 0,
          deliveriesProposed: 0,
          deliveriesEnqueued: 0,
          pushPending: 0,
          pushSent: 0,
          pushRetried: 0,
          pushFailed: 0,
          invalidTokens: 0,
        ),
      );
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'status': status,
          'runId': runId,
          'softBudgetExceeded': control.softBudgetExceeded,
          'hardBudgetExceeded': control.hardBudgetExceeded,
        }),
      );
      return;
    }

    final provider = ProviderGateway(config: config);
    final engine = RainAlertEngine(
      store: store,
      provider: ProviderRainAlertNowcast(provider),
      cellSizeDegrees: config.rainAlertCellSizeDegrees,
      maximumConcurrentCells: config.rainAlertMaxConcurrentCells,
      enqueueDeliveries: control.maySend,
      localTime: (utc, name) {
        try {
          return time_zone.TZDateTime.from(
            utc.toUtc(),
            time_zone.getLocation(name),
          );
        } on time_zone.LocationNotFoundException {
          return utc.toUtc();
        }
      },
    );
    final run = await engine.run();
    final dispatch = run.skippedBecauseLocked || !control.maySend
        ? const PushDispatchReport(
            pending: 0,
            sent: 0,
            retried: 0,
            failed: 0,
            invalidTokens: 0,
          )
        : await (() async {
            sender = await FirebaseRainAlertPushSender.connect(
              projectId: config.googleCloudProject!,
            );
            return RainAlertPushDispatcher(
              store: store,
              sender: sender!,
            ).flush();
          })();
    stopwatch.stop();
    final status = run.skippedBecauseLocked ? 'locked' : 'completed';
    final mode = control.maySend ? 'send' : 'shadow';
    await store.recordRunMetric(
      RainAlertRunMetric(
        runId: run.runId,
        startedAt: startedAt,
        durationMilliseconds: stopwatch.elapsedMilliseconds,
        mode: mode,
        status: status,
        activeAlerts: run.activeAlerts,
        cellsEvaluated: run.cellsEvaluated,
        providerFailures: run.providerFailures,
        alertsEvaluated: run.alertsEvaluated,
        deliveriesProposed: run.deliveriesProposed,
        deliveriesEnqueued: run.deliveriesEnqueued,
        pushPending: dispatch.pending,
        pushSent: dispatch.sent,
        pushRetried: dispatch.retried,
        pushFailed: dispatch.failed,
        invalidTokens: dispatch.invalidTokens,
      ),
    );
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': status,
        'mode': mode,
        'runId': run.runId,
        'activeAlerts': run.activeAlerts,
        'cellsEvaluated': run.cellsEvaluated,
        'providerFailures': run.providerFailures,
        'alertsEvaluated': run.alertsEvaluated,
        'deliveriesProposed': run.deliveriesProposed,
        'deliveriesEnqueued': run.deliveriesEnqueued,
        'pushPending': dispatch.pending,
        'pushSent': dispatch.sent,
        'pushRetried': dispatch.retried,
        'pushFailed': dispatch.failed,
        'invalidTokens': dispatch.invalidTokens,
        'durationMilliseconds': stopwatch.elapsedMilliseconds,
        'softBudgetExceeded': control.softBudgetExceeded,
      }),
    );
  } on Object catch (error, stackTrace) {
    stopwatch.stop();
    final runId = 'error-${startedAt.millisecondsSinceEpoch}';
    try {
      await store.recordRunMetric(
        RainAlertRunMetric(
          runId: runId,
          startedAt: startedAt,
          durationMilliseconds: stopwatch.elapsedMilliseconds,
          mode: 'unknown',
          status: 'failed',
          activeAlerts: 0,
          cellsEvaluated: 0,
          providerFailures: 0,
          alertsEvaluated: 0,
          deliveriesProposed: 0,
          deliveriesEnqueued: 0,
          pushPending: 0,
          pushSent: 0,
          pushRetried: 0,
          pushFailed: 1,
          invalidTokens: 0,
        ),
      );
    } on Object {
      // The original worker failure remains authoritative when metrics storage
      // is unavailable as well.
    }
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'status': 'failed',
        'runId': runId,
        'errorType': error.runtimeType.toString(),
        'durationMilliseconds': stopwatch.elapsedMilliseconds,
      }),
    );
    Error.throwWithStackTrace(error, stackTrace);
  } finally {
    await sender?.close();
    await store.close();
  }
}
