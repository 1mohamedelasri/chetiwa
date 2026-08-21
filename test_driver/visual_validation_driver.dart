import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final screenshots = data?['screenshots'] as List<dynamic>? ?? const [];
    final output = Directory('docs/quality/screenshots');
    await output.create(recursive: true);

    for (final raw in screenshots) {
      final screenshot = raw as Map<String, dynamic>;
      final name = screenshot['screenshotName'] as String;
      final bytes = (screenshot['bytes'] as List<dynamic>).cast<int>();
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
    }
  },
);
