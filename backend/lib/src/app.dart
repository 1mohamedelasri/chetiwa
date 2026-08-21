import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'api_exception.dart';
import 'device_alert_store.dart';
import 'json_response_cache.dart';
import 'provider_gateway.dart';
import 'request_rate_limiter.dart';
import 'runtime_config.dart';

typedef _Loader = Future<Map<String, Object?>> Function();

Handler createApp({
  required RuntimeConfig config,
  ProviderGateway? providers,
  JsonResponseCache? cache,
  RequestRateLimiter? rateLimiter,
  DeviceAlertStore? deviceAlertStore,
  DateTime Function()? now,
}) {
  final gateway = providers ?? ProviderGateway(config: config);
  final responseCache = cache ?? JsonResponseCache();
  final clock = now ?? DateTime.now;
  final limiter = rateLimiter ?? RequestRateLimiter();
  final stateStore =
      deviceAlertStore ??
      (config.environment == AppEnvironment.local
          ? InMemoryDeviceAlertStore(now: clock)
          : const UnavailableDeviceAlertStore());

  final router = Router()
    ..get('/healthz', (Request request) {
      return _jsonResponse(<String, Object?>{'status': 'ok'});
    })
    ..get('/readyz', (Request request) {
      return _jsonResponse(<String, Object?>{
        'status': 'ready',
        'environment': config.environment.name,
      });
    })
    ..get('/v1', (Request request) {
      return _jsonResponse(<String, Object?>{
        'service': 'chetiwa-api',
        'apiVersion': 'v1',
        'environment': config.environment.name,
      });
    })
    ..get('/v1/forecast', (Request request) async {
      try {
        final latitude = _coordinate(request, 'latitude', -90, 90);
        final longitude = _coordinate(request, 'longitude', -180, 180);
        return await _serveCached(
          request: request,
          cache: responseCache,
          now: clock,
          key: 'forecast:${_coordinateKey(latitude, longitude)}',
          policy: const CachePolicy(
            freshFor: Duration(minutes: 5),
            staleIfErrorFor: Duration(hours: 6),
          ),
          loader: () =>
              gateway.forecast(latitude: latitude, longitude: longitude),
        );
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..get('/v1/locations/search', (Request request) async {
      try {
        final query = _requiredQuery(request, 'q');
        if (query.length < 2 || query.length > 120) {
          throw const ApiException(
            statusCode: 400,
            code: 'invalid_query',
            message: 'q must contain between 2 and 120 characters',
          );
        }
        final language = _language(request);
        final count = _integerQuery(
          request,
          'count',
          fallback: 8,
          min: 1,
          max: 12,
        );
        final normalizedQuery = query.toLowerCase();
        return await _serveCached(
          request: request,
          cache: responseCache,
          now: clock,
          key: 'location-search:$language:$count:$normalizedQuery',
          policy: const CachePolicy(
            freshFor: Duration(hours: 24),
            staleIfErrorFor: Duration(days: 7),
          ),
          loader: () => gateway.searchLocations(
            query: query,
            language: language,
            count: count,
          ),
        );
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..get('/v1/locations/reverse', (Request request) async {
      try {
        final latitude = _coordinate(request, 'latitude', -90, 90);
        final longitude = _coordinate(request, 'longitude', -180, 180);
        final language = _language(request);
        return await _serveCached(
          request: request,
          cache: responseCache,
          now: clock,
          key:
              'location-reverse:$language:${_coordinateKey(latitude, longitude)}',
          policy: const CachePolicy(
            freshFor: Duration(hours: 24),
            staleIfErrorFor: Duration(days: 7),
          ),
          loader: () => gateway.reverseLocation(
            latitude: latitude,
            longitude: longitude,
            language: language,
          ),
        );
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..get('/v1/radar/frames', (Request request) async {
      try {
        final latitude = _coordinate(request, 'latitude', -90, 90);
        final longitude = _coordinate(request, 'longitude', -180, 180);
        return await _serveCached(
          request: request,
          cache: responseCache,
          now: clock,
          key: 'radar:${_coordinateKey(latitude, longitude)}',
          policy: const CachePolicy(
            freshFor: Duration(minutes: 2),
            staleIfErrorFor: Duration(minutes: 30),
          ),
          loader: () =>
              gateway.radarFrames(latitude: latitude, longitude: longitude),
        );
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..post('/v1/devices', (Request request) async {
      try {
        final ownerHash = _installationOwnerHash(request);
        final body = await _readJsonObject(request);
        final registration = _deviceRegistration(body);
        final device = await stateStore.upsertDevice(ownerHash, registration);
        return _dataResponse(
          <String, Object?>{'device': _deviceJson(device)},
          now: clock,
          statusCode: 201,
        );
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..delete('/v1/devices', (Request request) async {
      try {
        final ownerHash = _installationOwnerHash(request);
        final deleted = await stateStore.deleteDevice(ownerHash);
        if (!deleted) {
          throw const ApiException(
            statusCode: 404,
            code: 'device_not_found',
            message: 'No registered device was found',
          );
        }
        return Response(204);
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..get('/v1/alerts', (Request request) async {
      try {
        final ownerHash = _installationOwnerHash(request);
        final alerts = await stateStore.listAlerts(ownerHash);
        return _dataResponse(<String, Object?>{
          'alerts': alerts.map(_alertJson).toList(growable: false),
        }, now: clock);
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..post('/v1/alerts', (Request request) async {
      try {
        final ownerHash = _installationOwnerHash(request);
        final body = await _readJsonObject(request);
        final alert = await stateStore.createAlert(
          ownerHash,
          _alertDraft(body),
        );
        return _dataResponse(
          <String, Object?>{'alert': _alertJson(alert)},
          now: clock,
          statusCode: 201,
        );
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..patch('/v1/alerts/<alertId>', (Request request, String alertId) async {
      try {
        final ownerHash = _installationOwnerHash(request);
        _validateAlertId(alertId);
        final body = await _readJsonObject(request);
        final changes = _alertChanges(body);
        if (changes.isEmpty) {
          throw const ApiException(
            statusCode: 400,
            code: 'empty_patch',
            message: 'At least one alert field must be provided',
          );
        }
        final alert = await stateStore.updateAlert(ownerHash, alertId, changes);
        if (alert == null) {
          throw const ApiException(
            statusCode: 404,
            code: 'alert_not_found',
            message: 'The alert rule was not found',
          );
        }
        return _dataResponse(<String, Object?>{
          'alert': _alertJson(alert),
        }, now: clock);
      } on ApiException catch (error) {
        return _apiError(error);
      }
    })
    ..delete('/v1/alerts/<alertId>', (Request request, String alertId) async {
      try {
        final ownerHash = _installationOwnerHash(request);
        _validateAlertId(alertId);
        final deleted = await stateStore.deleteAlert(ownerHash, alertId);
        if (!deleted) {
          throw const ApiException(
            statusCode: 404,
            code: 'alert_not_found',
            message: 'The alert rule was not found',
          );
        }
        return Response(204);
      } on ApiException catch (error) {
        return _apiError(error);
      }
    });

  return const Pipeline()
      .addMiddleware(_responseHeaders())
      .addMiddleware(_gzipResponses())
      .addMiddleware(_rateLimit(limiter, clock))
      .addHandler(router.call);
}

Future<Response> _serveCached({
  required Request request,
  required JsonResponseCache cache,
  required DateTime Function() now,
  required String key,
  required CachePolicy policy,
  required _Loader loader,
}) async {
  final instant = now().toUtc();
  final existing = cache.read(key);
  if (existing != null && existing.isFresh(instant, policy)) {
    return _cachedResponse(
      request,
      existing,
      cacheStatus: 'HIT',
      policy: policy,
    );
  }

  try {
    final data = await loader();
    final body = jsonEncode(<String, Object?>{
      'data': data,
      'meta': <String, Object?>{'generatedAt': instant.toIso8601String()},
    });
    final etag = '"${sha256.convert(utf8.encode(body))}"';
    final entry = CachedJsonResponse(body: body, etag: etag, storedAt: instant);
    cache.write(key, entry);
    return _cachedResponse(request, entry, cacheStatus: 'MISS', policy: policy);
  } on ApiException catch (error) {
    if (existing != null && existing.canServeStale(instant, policy)) {
      return _staleResponse(request, existing, policy);
    }
    return _apiError(error);
  } catch (_) {
    if (existing != null && existing.canServeStale(instant, policy)) {
      return _staleResponse(request, existing, policy);
    }
    return _apiError(
      const ApiException(
        statusCode: 500,
        code: 'internal_error',
        message: 'The request could not be completed',
      ),
    );
  }
}

Response _staleResponse(
  Request request,
  CachedJsonResponse entry,
  CachePolicy policy,
) => _cachedResponse(
  request,
  entry,
  cacheStatus: 'STALE',
  policy: policy,
  warning: '110 - "Response is stale"',
);

Response _cachedResponse(
  Request request,
  CachedJsonResponse entry, {
  required String cacheStatus,
  required CachePolicy policy,
  String? warning,
}) {
  final headers = <String, String>{
    'content-type': 'application/json; charset=utf-8',
    'cache-control':
        'public, max-age=${policy.freshFor.inSeconds}, '
        'stale-if-error=${policy.staleIfErrorFor.inSeconds}',
    'etag': entry.etag,
    'x-cache': cacheStatus,
    if (warning != null) 'warning': warning,
  };
  if (request.headers['if-none-match'] == entry.etag) {
    return Response.notModified(headers: headers);
  }
  return Response.ok(entry.body, headers: headers);
}

String _coordinateKey(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';

String _installationOwnerHash(Request request) {
  final installationId = request.headers['x-chetiwa-device-id']?.trim();
  if (installationId == null || installationId.isEmpty) {
    throw const ApiException(
      statusCode: 401,
      code: 'missing_installation_id',
      message: 'X-Chetiwa-Device-Id is required',
    );
  }
  if (!RegExp(r'^[A-Za-z0-9._-]{8,128}$').hasMatch(installationId)) {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_installation_id',
      message: 'X-Chetiwa-Device-Id has an invalid format',
    );
  }
  return sha256.convert(utf8.encode(installationId)).toString();
}

Future<Map<String, Object?>> _readJsonObject(
  Request request, {
  int maximumBytes = 16 * 1024,
}) async {
  final contentLength = request.contentLength;
  if (contentLength != null && contentLength > maximumBytes) {
    throw const ApiException(
      statusCode: 413,
      code: 'payload_too_large',
      message: 'The JSON payload is too large',
    );
  }
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maximumBytes) {
      throw const ApiException(
        statusCode: 413,
        code: 'payload_too_large',
        message: 'The JSON payload is too large',
      );
    }
  }
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const ApiException(
        statusCode: 400,
        code: 'invalid_json',
        message: 'The request body must be a JSON object',
      );
    }
    return decoded;
  } on ApiException {
    rethrow;
  } on FormatException {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_json',
      message: 'The request body is not valid JSON',
    );
  }
}

DeviceRegistration _deviceRegistration(Map<String, Object?> body) {
  final platform = _requiredString(body, 'platform', maximumLength: 16);
  if (platform != 'ios' && platform != 'android') {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_platform',
      message: 'platform must be ios or android',
    );
  }
  final locale = _requiredString(body, 'locale', maximumLength: 8);
  if (locale != 'fr' && locale != 'en') {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_locale',
      message: 'locale must be fr or en',
    );
  }
  final timeZone = _requiredString(body, 'timeZone', maximumLength: 64);
  final notificationsEnabled = _optionalBool(
    body,
    'notificationsEnabled',
    fallback: false,
  );
  final pushToken = _optionalString(body, 'pushToken', maximumLength: 4096);
  if (notificationsEnabled && pushToken == null) {
    throw const ApiException(
      statusCode: 400,
      code: 'missing_push_token',
      message: 'pushToken is required when notifications are enabled',
    );
  }
  return DeviceRegistration(
    platform: platform,
    locale: locale,
    timeZone: timeZone,
    notificationsEnabled: notificationsEnabled,
    pushToken: pushToken,
  );
}

AlertRuleDraft _alertDraft(Map<String, Object?> body) => AlertRuleDraft(
  location: _alertLocation(_requiredObject(body, 'location')),
  leadMinutes: _leadMinutes(body['leadMinutes']),
  minimumIntensity: _minimumIntensity(body['minimumIntensity']),
  quietHours: _quietHours(_requiredObject(body, 'quietHours')),
  enabled: _requiredBool(body, 'enabled'),
);

AlertRuleChanges _alertChanges(Map<String, Object?> body) => AlertRuleChanges(
  location: body.containsKey('location')
      ? _alertLocation(_requiredObject(body, 'location'))
      : null,
  leadMinutes: body.containsKey('leadMinutes')
      ? _leadMinutes(body['leadMinutes'])
      : null,
  minimumIntensity: body.containsKey('minimumIntensity')
      ? _minimumIntensity(body['minimumIntensity'])
      : null,
  quietHours: body.containsKey('quietHours')
      ? _quietHours(_requiredObject(body, 'quietHours'))
      : null,
  enabled: body.containsKey('enabled') ? _requiredBool(body, 'enabled') : null,
);

AlertLocation _alertLocation(Map<String, Object?> body) {
  final latitude = _numberField(body, 'latitude', -90, 90);
  final longitude = _numberField(body, 'longitude', -180, 180);
  return AlertLocation(
    label: _requiredString(body, 'label', maximumLength: 120),
    latitude: latitude,
    longitude: longitude,
    timeZone: _requiredString(body, 'timeZone', maximumLength: 64),
  );
}

QuietHours _quietHours(Map<String, Object?> body) {
  final start = _requiredString(body, 'start', maximumLength: 5);
  final end = _requiredString(body, 'end', maximumLength: 5);
  final timePattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  if (!timePattern.hasMatch(start) || !timePattern.hasMatch(end)) {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_quiet_hours',
      message: 'quiet hour times must use the HH:mm format',
    );
  }
  return QuietHours(
    enabled: _requiredBool(body, 'enabled'),
    start: start,
    end: end,
  );
}

int _leadMinutes(Object? value) {
  if (value is! int || value < 5 || value > 120) {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_lead_minutes',
      message: 'leadMinutes must be an integer between 5 and 120',
    );
  }
  return value;
}

String _minimumIntensity(Object? value) {
  if (value is! String ||
      !const <String>{'light', 'moderate', 'heavy'}.contains(value)) {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_minimum_intensity',
      message: 'minimumIntensity must be light, moderate or heavy',
    );
  }
  return value;
}

void _validateAlertId(String alertId) {
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(alertId)) {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_alert_id',
      message: 'The alert identifier has an invalid format',
    );
  }
}

Map<String, Object?> _deviceJson(DeviceRecord device) => <String, Object?>{
  'registered': true,
  'platform': device.platform,
  'locale': device.locale,
  'timeZone': device.timeZone,
  'notificationsEnabled': device.notificationsEnabled,
  'createdAt': device.createdAt.toIso8601String(),
  'updatedAt': device.updatedAt.toIso8601String(),
};

Map<String, Object?> _alertJson(AlertRuleRecord alert) => <String, Object?>{
  'id': alert.id,
  'location': <String, Object?>{
    'label': alert.location.label,
    'latitude': alert.location.latitude,
    'longitude': alert.location.longitude,
    'timeZone': alert.location.timeZone,
  },
  'leadMinutes': alert.leadMinutes,
  'minimumIntensity': alert.minimumIntensity,
  'quietHours': <String, Object?>{
    'enabled': alert.quietHours.enabled,
    'start': alert.quietHours.start,
    'end': alert.quietHours.end,
  },
  'enabled': alert.enabled,
  'createdAt': alert.createdAt.toIso8601String(),
  'updatedAt': alert.updatedAt.toIso8601String(),
};

Map<String, Object?> _requiredObject(Map<String, Object?> body, String name) {
  final value = body[name];
  if (value is! Map<String, Object?>) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must be a JSON object',
    );
  }
  return value;
}

String _requiredString(
  Map<String, Object?> body,
  String name, {
  required int maximumLength,
}) {
  final value = body[name];
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maximumLength) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must contain between 1 and $maximumLength characters',
    );
  }
  return value.trim();
}

String? _optionalString(
  Map<String, Object?> body,
  String name, {
  required int maximumLength,
}) {
  final value = body[name];
  if (value == null) return null;
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maximumLength) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must contain between 1 and $maximumLength characters',
    );
  }
  return value.trim();
}

bool _requiredBool(Map<String, Object?> body, String name) {
  final value = body[name];
  if (value is! bool) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must be a boolean',
    );
  }
  return value;
}

bool _optionalBool(
  Map<String, Object?> body,
  String name, {
  required bool fallback,
}) {
  if (!body.containsKey(name)) return fallback;
  return _requiredBool(body, name);
}

double _numberField(
  Map<String, Object?> body,
  String name,
  double minimum,
  double maximum,
) {
  final raw = body[name];
  if (raw is! num) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must be between $minimum and $maximum',
    );
  }
  final value = raw.toDouble();
  if (!value.isFinite || value < minimum || value > maximum) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must be between $minimum and $maximum',
    );
  }
  return value;
}

Response _dataResponse(
  Map<String, Object?> data, {
  required DateTime Function() now,
  int statusCode = 200,
}) => _jsonResponse(<String, Object?>{
  'data': data,
  'meta': <String, Object?>{'generatedAt': now().toUtc().toIso8601String()},
}, statusCode: statusCode);

double _coordinate(Request request, String name, double min, double max) {
  final raw = _requiredQuery(request, name);
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite || value < min || value > max) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must be between $min and $max',
    );
  }
  return value;
}

String _requiredQuery(Request request, String name) {
  final value = request.url.queryParameters[name]?.trim();
  if (value == null || value.isEmpty) {
    throw ApiException(
      statusCode: 400,
      code: 'missing_$name',
      message: '$name is required',
    );
  }
  return value;
}

String _language(Request request) {
  final language =
      request.url.queryParameters['language']?.trim().toLowerCase() ?? 'fr';
  if (language != 'fr' && language != 'en') {
    throw const ApiException(
      statusCode: 400,
      code: 'invalid_language',
      message: 'language must be fr or en',
    );
  }
  return language;
}

int _integerQuery(
  Request request,
  String name, {
  required int fallback,
  required int min,
  required int max,
}) {
  final raw = request.url.queryParameters[name];
  if (raw == null) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value < min || value > max) {
    throw ApiException(
      statusCode: 400,
      code: 'invalid_$name',
      message: '$name must be between $min and $max',
    );
  }
  return value;
}

Response _apiError(ApiException error) => _jsonResponse(<String, Object?>{
  'error': <String, Object?>{'code': error.code, 'message': error.message},
}, statusCode: error.statusCode);

Response _jsonResponse(Map<String, Object?> body, {int statusCode = 200}) =>
    Response(
      statusCode,
      body: jsonEncode(body),
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
      },
    );

Middleware _responseHeaders() => (Handler innerHandler) {
  return (Request request) async {
    final response = await innerHandler(request);
    return response.change(
      headers: <String, String>{
        ...response.headers,
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'no-referrer',
      },
    );
  };
};

Middleware _rateLimit(RequestRateLimiter limiter, DateTime Function() now) =>
    (Handler innerHandler) {
      return (Request request) async {
        if (!request.url.path.startsWith('v1/')) {
          return innerHandler(request);
        }
        final decision = limiter.evaluate(_clientKey(request), now());
        final headers = <String, String>{
          'x-ratelimit-limit': decision.limit.toString(),
          'x-ratelimit-remaining': decision.remaining.toString(),
        };
        if (!decision.allowed) {
          return _jsonResponse(const <String, Object?>{
            'error': <String, Object?>{
              'code': 'rate_limit_exceeded',
              'message': 'Too many requests; retry later',
            },
          }, statusCode: 429).change(
            headers: <String, String>{
              ...headers,
              'retry-after': decision.retryAfter.inSeconds
                  .clamp(1, 60)
                  .toString(),
            },
          );
        }
        final response = await innerHandler(request);
        return response.change(headers: headers);
      };
    };

String _clientKey(Request request) {
  final deviceId = request.headers['x-chetiwa-device-id'];
  if (deviceId != null &&
      RegExp(r'^[A-Za-z0-9._-]{8,128}$').hasMatch(deviceId)) {
    return 'device:$deviceId';
  }
  final forwarded = request.headers['x-forwarded-for']?.split(',').first.trim();
  if (forwarded != null && forwarded.isNotEmpty && forwarded.length <= 64) {
    return 'ip:$forwarded';
  }
  final connection = request.context['shelf.io.connection_info'];
  if (connection is HttpConnectionInfo) {
    return 'ip:${connection.remoteAddress.address}';
  }
  return 'ip:unknown';
}

Middleware _gzipResponses() => (Handler innerHandler) {
  return (Request request) async {
    final acceptsGzip =
        request.headers['accept-encoding']
            ?.split(',')
            .map((value) => value.trim().split(';').first)
            .contains('gzip') ??
        false;
    final response = await innerHandler(request);
    final contentType = response.headers['content-type'] ?? '';
    if (!acceptsGzip ||
        response.statusCode == 204 ||
        response.statusCode == 304 ||
        !contentType.startsWith('application/json')) {
      return response;
    }
    final bytes = await response.read().fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    if (bytes.length < 512) {
      return Response(
        response.statusCode,
        body: bytes,
        headers: response.headers,
        context: response.context,
      );
    }
    final headers = <String, Object>{
      for (final entry in response.headers.entries)
        if (entry.key != 'content-length') entry.key: entry.value,
      'content-encoding': 'gzip',
      'vary': _appendVary(response.headers['vary'], 'accept-encoding'),
    };
    return Response(
      response.statusCode,
      body: gzip.encode(bytes),
      headers: headers,
      context: response.context,
    );
  };
};

String _appendVary(String? current, String value) {
  if (current == null || current.isEmpty) return value;
  final values = current.split(',').map((item) => item.trim().toLowerCase());
  return values.contains(value) ? current : '$current, $value';
}
