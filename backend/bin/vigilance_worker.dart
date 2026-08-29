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
    final reports = <({String provider, VigilanceRunReport report})>[];
    final failures = <String>[];
    final hasMeteoFrance =
        config.meteoFranceVigilanceApiKey != null ||
        config.meteoFranceApplicationId != null;
    var meteoFranceSucceeded = false;
    if (hasMeteoFrance) {
      try {
        final provider = MeteoFranceVigilanceProvider(
          client: client,
          apiKey: config.meteoFranceVigilanceApiKey,
          applicationId: config.meteoFranceApplicationId,
          tokenUri: config.meteoFranceTokenUri,
          productUri: config.meteoFranceVigilanceUri,
        );
        final report = await VigilanceAlertEngine(
          store: store,
          provider: provider,
          enqueueDeliveries: config.vigilanceAlertsSendEnabled,
          scope: VigilanceAlertScope.france,
        ).run();
        reports.add((provider: 'meteofrance', report: report));
        meteoFranceSucceeded = true;
      } on Object catch (error) {
        failures.add('meteofrance:${error.runtimeType}');
      }
    }
    if (config.meteoAlarmAlertsEnabled) {
      try {
        final apiKey = config.meteoAlarmApiKey;
        if (apiKey == null) {
          throw StateError('METEOALARM_API_KEY is required by the worker');
        }
        final provider = MeteoAlarmVigilanceProvider(
          client: client,
          apiKey: apiKey,
          warningsUri: config.meteoAlarmWarningsUri,
        );
        final report = await VigilanceAlertEngine(
          store: store,
          provider: provider,
          enqueueDeliveries: config.vigilanceAlertsSendEnabled,
          scope: meteoFranceSucceeded
              ? VigilanceAlertScope.outsideFrance
              : VigilanceAlertScope.all,
          source: 'meteoalarm',
          officialUrl: 'https://www.meteoalarm.org',
          sourceLabelFrench: 'MeteoAlarm',
          sourceLabelEnglish: 'MeteoAlarm',
        ).run();
        reports.add((provider: 'meteoalarm', report: report));
      } on Object catch (error) {
        failures.add('meteoalarm:${error.runtimeType}');
      }
    }
    if (reports.isEmpty && failures.isNotEmpty) {
      throw StateError('All official warning providers failed: $failures');
    }
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
        'status': failures.isEmpty ? 'completed' : 'partial',
        'mode': config.vigilanceAlertsSendEnabled ? 'send' : 'shadow',
        'providers': reports
            .map(
              (entry) => <String, Object?>{
                'provider': entry.provider,
                'snapshotId': entry.report.snapshotId,
                'activeAlerts': entry.report.activeAlerts,
                'alertsEvaluated': entry.report.alertsEvaluated,
                'deliveriesProposed': entry.report.deliveriesProposed,
                'deliveriesEnqueued': entry.report.deliveriesEnqueued,
              },
            )
            .toList(growable: false),
        if (failures.isNotEmpty) 'providerFailures': failures,
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
