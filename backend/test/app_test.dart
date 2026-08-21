import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final config = RuntimeConfig.fromEnvironment(const <String, String>{});
  final app = createApp(config: config);

  test('health endpoint is cache-safe JSON', () async {
    final response = await app(
      Request('GET', Uri.parse('http://localhost/healthz')),
    );

    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    expect(response.headers['x-content-type-options'], 'nosniff');
    expect(jsonDecode(await response.readAsString()), <String, Object>{
      'status': 'ok',
    });
  });

  test('version endpoint exposes the active environment', () async {
    final response = await app(
      Request('GET', Uri.parse('http://localhost/v1')),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;

    expect(response.statusCode, 200);
    expect(body['service'], 'chetiwa-api');
    expect(body['apiVersion'], 'v1');
    expect(body['environment'], 'local');
  });
}
