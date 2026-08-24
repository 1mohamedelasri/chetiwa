import 'dart:async';
import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--healthcheck')) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:8080/healthz'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>();
      exitCode = response.statusCode == HttpStatus.ok ? 0 : 1;
    } on Object {
      exitCode = 1;
    } finally {
      client.close(force: true);
    }
    return;
  }

  final config = RuntimeConfig.fromEnvironment();
  // Forecast, location and Radar must remain deployable without enabling a
  // billable Firestore project. Alert routes already fail closed through
  // UnavailableDeviceAlertStore when no store is supplied. Connect Firestore
  // only when the remote alert engine is explicitly enabled.
  final persistentAlerts =
      config.environment == AppEnvironment.local ||
          (!config.rainAlertsEnabled && !config.rainAlertsSendEnabled)
      ? null
      : await FirestoreDeviceAlertStore.connect(
          projectId: config.googleCloudProject!,
          databaseId: config.firestoreDatabaseId,
        );
  final server = await shelf_io.serve(
    createApp(config: config, deviceAlertStore: persistentAlerts),
    InternetAddress.anyIPv4,
    config.port,
    poweredByHeader: null,
  );

  stdout.writeln(
    'Chetiwa API (${config.environment.name}) listening on '
    '${server.address.host}:${server.port}',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Received ${signal.name}; stopping Chetiwa API');
    await server.close(force: true);
    await persistentAlerts?.close();
    exitCode = 0;
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
