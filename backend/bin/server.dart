import 'dart:async';
import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final config = RuntimeConfig.fromEnvironment();
  final server = await shelf_io.serve(
    createApp(config: config),
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
    exitCode = 0;
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
