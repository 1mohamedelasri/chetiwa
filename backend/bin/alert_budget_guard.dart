import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final config = RuntimeConfig.fromEnvironment();
  if (config.environment == AppEnvironment.local ||
      config.googleCloudProject == null) {
    throw StateError(
      'alert_budget_guard requires staging/production and GOOGLE_CLOUD_PROJECT',
    );
  }
  final store = await FirestoreDeviceAlertStore.connect(
    projectId: config.googleCloudProject!,
    databaseId: config.firestoreDatabaseId,
  );
  final fallback = RainAlertRuntimeControl(
    engineEnabled: config.rainAlertsEnabled,
    sendEnabled: config.rainAlertsSendEnabled,
    observedCostCents: 0,
    softBudgetCents: config.rainAlertSoftBudgetCents,
    hardBudgetCents: config.rainAlertHardBudgetCents,
  );
  final server = await shelf_io.serve(
    createRainAlertBudgetGuard(
      store: store,
      fallbackControl: fallback,
      expectedCurrency: config.rainAlertBudgetCurrency,
    ),
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln(
    '{"status":"ready","service":"alert-budget-guard",'
    '"port":${server.port}}',
  );
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    await store.close();
  });
}
