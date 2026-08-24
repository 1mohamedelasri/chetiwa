import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final instant = DateTime.utc(2026, 8, 20, 18, 30);

  Handler localApp() {
    var id = 0;
    return createApp(
      config: RuntimeConfig.fromEnvironment(const <String, String>{}),
      now: () => instant,
      deviceAlertStore: InMemoryDeviceAlertStore(
        now: () => instant,
        idGenerator: () => (++id).toRadixString(16).padLeft(32, '0'),
      ),
    );
  }

  test('device registration requires an installation identity', () async {
    final response = await localApp()(
      _jsonRequest('POST', '/v1/devices', _deviceBody(), deviceId: null),
    );

    expect(response.statusCode, 401);
    expect(await _errorCode(response), 'missing_installation_id');
  });

  test('registers a device without exposing its token or owner hash', () async {
    final response = await localApp()(
      _jsonRequest('POST', '/v1/devices', _deviceBody()),
    );
    final body = await _body(response);
    final device =
        (body['data'] as Map<String, Object?>)['device']
            as Map<String, Object?>;

    expect(response.statusCode, 201);
    expect(device['registered'], isTrue);
    expect(device['notificationsEnabled'], isTrue);
    expect(jsonEncode(body), isNot(contains('secret-push-token')));
    expect(jsonEncode(body), isNot(contains('ownerHash')));
  });

  test('supports isolated alert CRUD and device cascade deletion', () async {
    final app = localApp();
    await app(_jsonRequest('POST', '/v1/devices', _deviceBody()));
    await app(
      _jsonRequest(
        'POST',
        '/v1/devices',
        _deviceBody(),
        deviceId: 'other-device-456',
      ),
    );

    final createdResponse = await app(
      _jsonRequest('POST', '/v1/alerts', _alertBody()),
    );
    final createdBody = await _body(createdResponse);
    final alert =
        (createdBody['data'] as Map<String, Object?>)['alert']
            as Map<String, Object?>;
    final alertId = alert['id']! as String;

    expect(createdResponse.statusCode, 201);
    expect(alert['minimumIntensity'], 'moderate');

    final listResponse = await app(_request('GET', '/v1/alerts'));
    final listBody = await _body(listResponse);
    final alerts = (listBody['data'] as Map<String, Object?>)['alerts'] as List;
    expect(alerts, hasLength(1));

    final otherList = await app(
      _request('GET', '/v1/alerts', deviceId: 'other-device-456'),
    );
    final otherBody = await _body(otherList);
    expect((otherBody['data'] as Map<String, Object?>)['alerts'], isEmpty);

    final foreignPatch = await app(
      _jsonRequest('PATCH', '/v1/alerts/$alertId', <String, Object?>{
        'enabled': false,
      }, deviceId: 'other-device-456'),
    );
    expect(foreignPatch.statusCode, 404);

    final patchResponse = await app(
      _jsonRequest('PATCH', '/v1/alerts/$alertId', <String, Object?>{
        'enabled': false,
        'leadMinutes': 30,
      }),
    );
    final patched =
        ((await _body(patchResponse))['data'] as Map<String, Object?>)['alert']
            as Map<String, Object?>;
    expect(patched['enabled'], isFalse);
    expect(patched['leadMinutes'], 30);

    final deleteDevice = await app(_request('DELETE', '/v1/devices'));
    expect(deleteDevice.statusCode, 204);

    final listAfterDelete = await app(_request('GET', '/v1/alerts'));
    expect(listAfterDelete.statusCode, 409);
    expect(await _errorCode(listAfterDelete), 'device_not_registered');
  });

  test('deleting one alert leaves the registered device usable', () async {
    final app = localApp();
    await app(_jsonRequest('POST', '/v1/devices', _deviceBody()));
    final created = await app(_jsonRequest('POST', '/v1/alerts', _alertBody()));
    final alertId =
        (((await _body(created))['data'] as Map<String, Object?>)['alert']
            as Map<String, Object?>)['id']!;

    final deleted = await app(_request('DELETE', '/v1/alerts/$alertId'));
    expect(deleted.statusCode, 204);

    final list = await app(_request('GET', '/v1/alerts'));
    expect(list.statusCode, 200);
    expect(
      ((await _body(list))['data'] as Map<String, Object?>)['alerts'],
      isEmpty,
    );
  });

  test('rejects invalid alert values and excessive alert count', () async {
    final app = localApp();
    await app(_jsonRequest('POST', '/v1/devices', _deviceBody()));

    final invalid = _alertBody();
    invalid['minimumIntensity'] = 'catastrophic';
    final invalidResponse = await app(
      _jsonRequest('POST', '/v1/alerts', invalid),
    );
    expect(invalidResponse.statusCode, 400);
    expect(await _errorCode(invalidResponse), 'invalid_minimum_intensity');

    for (var index = 0; index < 5; index += 1) {
      final response = await app(
        _jsonRequest('POST', '/v1/alerts', _alertBody()),
      );
      expect(response.statusCode, 201);
    }
    final excessive = await app(
      _jsonRequest('POST', '/v1/alerts', _alertBody()),
    );
    expect(excessive.statusCode, 409);
    expect(await _errorCode(excessive), 'alert_limit_reached');
  });

  test('validates quiet hours, coordinates and JSON size', () async {
    final app = localApp();
    await app(_jsonRequest('POST', '/v1/devices', _deviceBody()));

    final invalidQuiet = _alertBody();
    invalidQuiet['quietHours'] = <String, Object?>{
      'enabled': true,
      'start': '25:00',
      'end': '07:00',
    };
    final quietResponse = await app(
      _jsonRequest('POST', '/v1/alerts', invalidQuiet),
    );
    expect(await _errorCode(quietResponse), 'invalid_quiet_hours');

    final invalidLocation = _alertBody();
    invalidLocation['location'] = <String, Object?>{
      ...invalidLocation['location']! as Map<String, Object?>,
      'latitude': 91,
    };
    final locationResponse = await app(
      _jsonRequest('POST', '/v1/alerts', invalidLocation),
    );
    expect(await _errorCode(locationResponse), 'invalid_latitude');

    final tooLarge = await app(
      _jsonRequest('POST', '/v1/devices', <String, Object?>{
        ..._deviceBody(),
        'pushToken': 'x' * 17000,
      }),
    );
    expect(tooLarge.statusCode, 413);
    expect(await _errorCode(tooLarge), 'payload_too_large');
  });

  test(
    'non-local profiles do not silently use ephemeral alert storage',
    () async {
      final app = createApp(
        config: RuntimeConfig.fromEnvironment(const <String, String>{
          'CHETIWA_ENV': 'production',
          'GOOGLE_CLOUD_PROJECT': 'chetiwa-production',
          'RADAR_ENABLED': 'false',
        }),
      );

      final response = await app(
        _jsonRequest('POST', '/v1/devices', _deviceBody()),
      );
      expect(response.statusCode, 503);
      expect(await _errorCode(response), 'persistent_store_not_configured');
    },
  );
}

Map<String, Object?> _deviceBody() => <String, Object?>{
  'platform': 'ios',
  'locale': 'fr',
  'timeZone': 'Europe/Paris',
  'notificationsEnabled': true,
  'pushToken': 'secret-push-token',
};

Map<String, Object?> _alertBody() => <String, Object?>{
  'location': <String, Object?>{
    'label': 'Paris, France',
    'latitude': 48.8566,
    'longitude': 2.3522,
    'timeZone': 'Europe/Paris',
  },
  'leadMinutes': 15,
  'minimumIntensity': 'moderate',
  'quietHours': <String, Object?>{
    'enabled': true,
    'start': '22:00',
    'end': '07:00',
  },
  'enabled': true,
};

Request _request(
  String method,
  String path, {
  String? deviceId = 'test-device-123',
  Object? body,
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: <String, String>{
    if (deviceId != null) 'x-chetiwa-device-id': deviceId,
    if (body != null) 'content-type': 'application/json',
  },
  body: body == null ? null : jsonEncode(body),
);

Request _jsonRequest(
  String method,
  String path,
  Object body, {
  String? deviceId = 'test-device-123',
}) => _request(method, path, deviceId: deviceId, body: body);

Future<Map<String, Object?>> _body(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, Object?>;

Future<String?> _errorCode(Response response) async =>
    ((await _body(response))['error'] as Map<String, Object?>)['code']
        as String?;
