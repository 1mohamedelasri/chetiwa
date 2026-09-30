import 'dart:io';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Handler app({bool trustedProxy = false}) => createApp(
    config: RuntimeConfig.fromEnvironment(<String, String>{
      'TRUST_CLOUDFLARE_PROXY': '$trustedProxy',
      'NETWORK_RATE_LIMIT_PER_MINUTE': '2',
      'RADAR_NETWORK_RATE_LIMIT_PER_MINUTE': '3',
    }),
  );

  Request request({
    required String device,
    String peer = '192.0.2.1',
    String? cloudflareIp,
    String? forwardedIp,
    String path = '/v1/app-config',
  }) => Request(
    'GET',
    Uri.parse('http://localhost$path'),
    headers: <String, String>{
      'x-chetiwa-device-id': device,
      if (cloudflareIp != null) 'cf-connecting-ip': cloudflareIp,
      if (forwardedIp != null) 'x-forwarded-for': forwardedIp,
    },
    context: <String, Object>{
      'shelf.io.connection_info': _ConnectionInfo(peer),
    },
  );

  test(
    'rotating device IDs and untrusted proxy headers cannot reset peer limit',
    () async {
      final handler = app();
      for (var index = 0; index < 3; index++) {
        final response = await handler(
          request(
            device: 'rotating-device-$index',
            cloudflareIp: '198.51.100.${index + 1}',
            forwardedIp: '203.0.113.${index + 1}',
          ),
        );
        expect(response.statusCode, index < 2 ? 200 : 429);
      }
      final otherPeer = await handler(
        request(device: 'another-device', peer: '192.0.2.2'),
      );
      expect(otherPeer.statusCode, 200);
    },
  );

  test(
    'trusted Cloudflare clients receive independent network budgets',
    () async {
      final handler = app(trustedProxy: true);
      for (var index = 0; index < 3; index++) {
        final response = await handler(
          request(
            device: 'rotating-device-$index',
            cloudflareIp: '198.51.100.1',
          ),
        );
        expect(response.statusCode, index < 2 ? 200 : 429);
      }
      expect(
        (await handler(
          request(device: 'another-device', cloudflareIp: '198.51.100.2'),
        )).statusCode,
        200,
      );
    },
  );

  test('trusted proxy mode rejects missing or ambiguous addresses', () async {
    final handler = app(trustedProxy: true);
    for (final ip in <String?>[
      null,
      '',
      '198.51.100.1, 198.51.100.2',
      'not-an-ip',
      'fe80::1%eth0',
    ]) {
      final response = await handler(
        request(device: 'valid-device-id', cloudflareIp: ip),
      );
      expect(response.statusCode, 400);
    }
    expect(
      (await handler(
        request(device: 'valid-device-id', cloudflareIp: '2001:db8::1'),
      )).statusCode,
      200,
    );
  });

  test('radar fan-out does not consume the JSON network budget', () async {
    final handler = app();
    for (var index = 0; index < 4; index++) {
      final response = await handler(
        request(
          device: 'radar-device-$index',
          // Malformed frames return 400 before provider I/O but still consume
          // the public request budget, just like a valid tile request.
          path: '/v1/radar/tiles/a/7/64/44',
        ),
      );
      expect(response.statusCode, index < 3 ? 400 : 429);
    }
    expect((await handler(request(device: 'json-device'))).statusCode, 200);
  });

  test('deployment defaults do not trust proxy-supplied identity', () {
    final config = RuntimeConfig.fromEnvironment(const <String, String>{});
    expect(config.trustCloudflareProxy, isFalse);
    expect(config.networkRateLimitPerMinute, 1200);
    expect(config.radarNetworkRateLimitPerMinute, 6000);
  });
}

final class _ConnectionInfo implements HttpConnectionInfo {
  _ConnectionInfo(String address) : remoteAddress = InternetAddress(address);

  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 50000;
  @override
  int get localPort => 8080;
}
