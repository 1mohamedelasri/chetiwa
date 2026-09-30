import 'dart:async';

import 'package:http/http.dart' as http;

/// Bounds both response headers and body, and releases the transport on timeout.
/// Future.timeout alone leaves its HTTP request running in the background.
Future<http.Response> boundedHttpRequest(
  http.Client client,
  String method,
  Uri uri, {
  required Duration timeout,
  Map<String, String> headers = const {},
  String? body,
  bool followRedirects = true,
}) async {
  final abort = Completer<void>();
  final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)
    ..headers.addAll(headers)
    ..followRedirects = followRedirects;
  if (body != null) request.body = body;

  return (() async {
    final response = await client.send(request);
    return http.Response.fromStream(response);
  })().timeout(
    timeout,
    onTimeout: () {
      abort.complete();
      throw TimeoutException('Upstream request timed out', timeout);
    },
  );
}
