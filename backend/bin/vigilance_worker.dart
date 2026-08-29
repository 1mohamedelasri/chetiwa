import 'dart:convert';
import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final config = RuntimeConfig.fromEnvironment();
  if (!config.vigilanceAlertsEnabled || config.globalKillSwitch) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'disabled',
        'vigilanceAlertsEnabled': config.vigilanceAlertsEnabled,
        'globalKillSwitch': config.globalKillSwitch,
      }),
    );
    return;
  }
  if (config.environment == AppEnvironment.local ||
      config.googleCloudProject == null) {
    throw StateError(
      'vigilance_worker requires staging/production and GOOGLE_CLOUD_PROJECT',
    );
  }

  final client = http.Client();
  final store = await FirestoreDeviceAlertStore.connect(
    projectId: config.googleCloudProject!,
    databaseId: config.firestoreDatabaseId,
    rainAlertCellSizeDegrees: config.rainAlertCellSizeDegrees,
  );
  FirebaseVigilancePushSender? sender;
  final stopwatch = Stopwatch()..start();
  try {
    final provider = MeteoFranceVigilanceProvider(
      client: client,
      apiKey: config.meteoFranceVigilanceApiKey,
      applicationId: config.meteoFranceApplicationId,
      tokenUri: config.meteoFranceTokenUri,
      productUri: config.meteoFranceVigilanceUri,
    );
    final run = await VigilanceAlertEngine(
      store: store,
      provider: provider,
      enqueueDeliveries: config.vigilanceAlertsSendEnabled,
    ).run();
    final dispatch = !config.vigilanceAlertsSendEnabled
        ? const VigilancePushDispatchReport(
            pending: 0,
            sent: 0,
            retried: 0,
            failed: 0,
            invalidTokens: 0,
          )
        : await (() async {
            sender = await FirebaseVigilancePushSender.connect(
              projectId: config.googleCloudProject!,
            );
            return VigilancePushDispatcher(
              store: store,
              sender: sender!,
            ).flush();
          })();
    stopwatch.stop();
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'completed',
        'mode': config.vigilanceAlertsSendEnabled ? 'send' : 'shadow',
        'snapshotId': run.snapshotId,
        'activeAlerts': run.activeAlerts,
        'alertsEvaluated': run.alertsEvaluated,
        'deliveriesProposed': run.deliveriesProposed,
        'deliveriesEnqueued': run.deliveriesEnqueued,
        'pushPending': dispatch.pending,
        'pushSent': dispatch.sent,
        'pushRetried': dispatch.retried,
        'pushFailed': dispatch.failed,
        'invalidTokens': dispatch.invalidTokens,
        'durationMilliseconds': stopwatch.elapsedMilliseconds,
      }),
    );
  } on Object catch (error, stackTrace) {
    stopwatch.stop();
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'status': 'failed',
        'errorType': error.runtimeType.toString(),
        'durationMilliseconds': stopwatch.elapsedMilliseconds,
      }),
    );
    Error.throwWithStackTrace(error, stackTrace);
  } finally {
    await sender?.close();
    client.close();
    await store.close();
  }
}
