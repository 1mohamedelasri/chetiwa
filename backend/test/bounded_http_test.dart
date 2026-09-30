import 'dart:async';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:chetiwa_backend/src/api_exception.dart';
import 'package:chetiwa_backend/src/bounded_http.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'timeout aborts an upstream still waiting for response headers',
    () async {
      final aborted = Completer<void>();
      final client = _Client((request) async {
        await (request as http.AbortableRequest).abortTrigger;
        aborted.complete();
        throw http.RequestAbortedException(request.url);
      });

      await expectLater(
        boundedHttpRequest(
          client,
          'GET',
          Uri.https('provider.example', '/data'),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await aborted.future.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'timeout includes body streaming and aborts a stalled response',
    () async {
      final body = StreamController<List<int>>();
      final aborted = Completer<void>();
      final client = _Client((request) async {
        (request as http.AbortableRequest).abortTrigger!.then((_) {
          aborted.complete();
          body.addError(http.RequestAbortedException(request.url));
          unawaited(body.close());
        });
        return http.StreamedResponse(body.stream, 200);
      });
      await expectLater(
        boundedHttpRequest(
          client,
          'GET',
          Uri.https('provider.example', '/data'),
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await aborted.future.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'provider retries share one deadline instead of three timeouts',
    () async {
      var calls = 0;
      final client = _Client((request) async {
        calls++;
        await (request as http.AbortableRequest).abortTrigger;
        throw http.RequestAbortedException(request.url);
      });
      final provider = ProviderGateway(
        config: RuntimeConfig.fromEnvironment(const {}),
        client: client,
        delay: (_) async {},
        jsonRequestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        provider.forecast(latitude: 48, longitude: 2),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'provider_unavailable',
          ),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'radar tiles refuse to follow a redirect away from configured origin',
    () async {
      final client = _Client((request) async {
        expect(request.url.host, 'api.librewxr.net');
        expect(request.followRedirects, isFalse);
        return http.StreamedResponse(
          Stream.value([]),
          302,
          headers: {'location': 'http://127.0.0.1/healthz'},
        );
      });
      final provider = ProviderGateway(
        config: RuntimeConfig.fromEnvironment(const {}),
        client: client,
      );
      await expectLater(
        provider.radarTile(frame: '/v2/radar/1776707400', z: 7, x: 64, y: 44),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'radar_tile_provider_rejected',
          ),
        ),
      );
    },
  );

  test('shared counters release their transport on timeout', () async {
    final aborted = Completer<void>();
    final client = _Client((request) async {
      await (request as http.AbortableRequest).abortTrigger;
      aborted.complete();
      throw http.RequestAbortedException(request.url);
    });
    final counter = HttpSharedCounter(
      endpoint: Uri.https('counter.example', '/increment'),
      client: client,
      requestTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      counter.increment('key', ttl: const Duration(minutes: 1)),
      throwsA(isA<TimeoutException>()),
    );
    await aborted.future.timeout(const Duration(seconds: 1));
  });
}

final class _Client extends http.BaseClient {
  _Client(this.onSend);
  final Future<http.StreamedResponse> Function(http.BaseRequest) onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);
}
