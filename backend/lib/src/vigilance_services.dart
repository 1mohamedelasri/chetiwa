import 'dart:convert';
import 'dart:io';

import 'package:googleapis/fcm/v1.dart' as fcm;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'device_alert_store.dart';
import 'vigilance_alert_engine.dart';

final class FrenchDepartment {
  const FrenchDepartment({required this.code, required this.name});

  final String code;
  final String name;
}

abstract interface class DepartmentResolver {
  Future<FrenchDepartment?> resolve({
    required double latitude,
    required double longitude,
  });
}

final class GeoApiDepartmentResolver implements DepartmentResolver {
  GeoApiDepartmentResolver({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse('https://geo.api.gouv.fr/communes');

  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<FrenchDepartment?> resolve({
    required double latitude,
    required double longitude,
  }) async {
    final uri = _endpoint.replace(
      queryParameters: <String, String>{
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'fields': 'nom,codeDepartement,departement',
        'format': 'json',
        'geometry': 'centre',
      },
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('geo.api.gouv.fr returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
      return null;
    }
    final commune = Map<String, Object?>.from(decoded.first as Map);
    final nested = commune['departement'];
    final department = nested is Map
        ? Map<String, Object?>.from(nested)
        : const <String, Object?>{};
    final code = (commune['codeDepartement'] ?? department['code'])
        ?.toString()
        .trim();
    final name = department['nom']?.toString().trim();
    if (code == null || code.isEmpty) return null;
    return FrenchDepartment(
      code: code.toUpperCase(),
      name: name == null || name.isEmpty ? code.toUpperCase() : name,
    );
  }
}

final class MeteoFranceVigilanceProvider implements VigilanceProvider {
  MeteoFranceVigilanceProvider({
    required http.Client client,
    String? apiKey,
    String? applicationId,
    Uri? tokenUri,
    Uri? productUri,
    DateTime Function()? now,
  }) : _client = client,
       _apiKey = _nonEmpty(apiKey),
       _applicationId = _nonEmpty(applicationId),
       _tokenUri =
           tokenUri ?? Uri.parse('https://portail-api.meteofrance.fr/token'),
       _productUri =
           productUri ??
           Uri.parse(
             'https://public-api.meteofrance.fr/public/DPVigilance/v1/cartevigilance/encours',
           ),
       _now = now ?? DateTime.now {
    if (_apiKey == null && _applicationId == null) {
      throw StateError(
        'METEO_FRANCE_VIGILANCE_API_KEY or METEO_FRANCE_APPLICATION_ID is required',
      );
    }
  }

  final http.Client _client;
  final String? _apiKey;
  final String? _applicationId;
  final Uri _tokenUri;
  final Uri _productUri;
  final DateTime Function() _now;
  String? _oauthToken;
  DateTime? _oauthTokenExpiresAt;

  @override
  Future<VigilanceSnapshot> current() async {
    final response = await _client
        .get(
          _productUri,
          headers: <String, String>{
            HttpHeaders.acceptHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer ${await _bearerToken()}',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError(
        'Meteo-France vigilance API returned ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Vigilance product must be a JSON object');
    }
    return parse(Map<String, Object?>.from(decoded));
  }

  Future<String> _bearerToken() async {
    final apiKey = _apiKey;
    if (apiKey != null) return apiKey;
    final now = _now().toUtc();
    if (_oauthToken case final token?
        when _oauthTokenExpiresAt?.isAfter(
              now.add(const Duration(minutes: 1)),
            ) ??
            false) {
      return token;
    }
    final response = await _client
        .post(
          _tokenUri,
          headers: <String, String>{
            HttpHeaders.authorizationHeader: 'Basic $_applicationId',
            HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
            HttpHeaders.acceptHeader: 'application/json',
          },
          body: 'grant_type=client_credentials',
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Meteo-France OAuth returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['access_token'] is! String) {
      throw const FormatException('Meteo-France OAuth response is invalid');
    }
    final expiresIn = _integer(decoded['expires_in']) ?? 3600;
    _oauthToken = decoded['access_token'] as String;
    _oauthTokenExpiresAt = now.add(Duration(seconds: expiresIn));
    return _oauthToken!;
  }

  static VigilanceSnapshot parse(Map<String, Object?> json) {
    final product = _map(json['product'], 'product');
    final meta = _map(json['meta'], 'meta');
    final productAt = _date(
      meta['product_datetime'] ?? product['update_time'],
      'product_datetime',
    );
    final snapshotId = meta['snapshot_id']?.toString().trim().isNotEmpty == true
        ? meta['snapshot_id']!.toString()
        : productAt.toIso8601String();
    final events = <VigilanceEvent>[];
    for (final rawPeriod in _list(product['periods'])) {
      final period = _map(rawPeriod, 'period');
      final periodStart = _date(
        period['begin_validity_time'],
        'begin_validity_time',
      );
      final periodEnd = _date(period['end_validity_time'], 'end_validity_time');
      final timelaps = _map(period['timelaps'], 'timelaps');
      for (final rawDomain in _list(timelaps['domain_ids'])) {
        final domain = _map(rawDomain, 'domain');
        final departmentCode = domain['domain_id']?.toString().toUpperCase();
        // Coastal subdomains such as 2910 are intentionally excluded: sending
        // a coastal warning to an entire inland department would be unsafe.
        if (departmentCode == null ||
            !RegExp(r'^(?:2A|2B|\d{2,3})$').hasMatch(departmentCode)) {
          continue;
        }
        for (final rawItem in _list(domain['phenomenon_items'])) {
          final item = _map(rawItem, 'phenomenon');
          final phenomenonId = _integer(item['phenomenon_id']);
          final maximumColor = _integer(item['phenomenon_max_color_id']);
          if (phenomenonId == null ||
              phenomenonId < 1 ||
              phenomenonId > 9 ||
              maximumColor == null ||
              maximumColor < 2 ||
              maximumColor > 4) {
            continue;
          }
          final phenomenon = VigilancePhenomenon.fromId(phenomenonId);
          final intervals = _list(item['timelaps_items']);
          if (intervals.isEmpty) {
            events.add(
              VigilanceEvent(
                departmentCode: departmentCode,
                phenomenon: phenomenon,
                level: VigilanceLevel.fromColorId(maximumColor),
                beginsAt: periodStart,
                endsAt: periodEnd,
              ),
            );
            continue;
          }
          for (final rawInterval in intervals) {
            final interval = _map(rawInterval, 'timelaps item');
            final color = _integer(interval['color_id']);
            if (color == null || color < 2 || color > 4) continue;
            final beginsAt = _date(interval['begin_time'], 'begin_time');
            final endsAt = _date(interval['end_time'], 'end_time');
            if (!endsAt.isAfter(beginsAt)) continue;
            events.add(
              VigilanceEvent(
                departmentCode: departmentCode,
                phenomenon: phenomenon,
                level: VigilanceLevel.fromColorId(color),
                beginsAt: beginsAt,
                endsAt: endsAt,
              ),
            );
          }
        }
      }
    }
    return VigilanceSnapshot(
      snapshotId: snapshotId,
      productAt: productAt,
      events: List<VigilanceEvent>.unmodifiable(events),
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map) throw FormatException('$field must be an object');
    return Map<String, Object?>.from(value);
  }

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];

  static DateTime _date(Object? value, String field) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) throw FormatException('$field must be an ISO date');
    return parsed.toUtc();
  }

  static int? _integer(Object? value) => switch (value) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };
}

final class FirebaseVigilancePushSender implements VigilancePushSender {
  FirebaseVigilancePushSender({
    required fcm.FirebaseCloudMessagingApi api,
    required String projectId,
    DateTime Function()? now,
    http.Client? ownedClient,
  }) : _api = api,
       _project = 'projects/$projectId',
       _now = now ?? DateTime.now,
       _ownedClient = ownedClient;

  static Future<FirebaseVigilancePushSender> connect({
    required String projectId,
  }) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const <String>[
        fcm.FirebaseCloudMessagingApi.firebaseMessagingScope,
      ],
    );
    return FirebaseVigilancePushSender(
      api: fcm.FirebaseCloudMessagingApi(client),
      projectId: projectId,
      ownedClient: client,
    );
  }

  final fcm.FirebaseCloudMessagingApi _api;
  final String _project;
  final DateTime Function() _now;
  final http.Client? _ownedClient;

  Future<void> close() async => _ownedClient?.close();

  @override
  Future<VigilancePushOutcome> send(PendingVigilanceDelivery delivery) async {
    final draft = delivery.draft;
    final expiration = draft.expiresAt
        .difference(_now().toUtc())
        .inSeconds
        .clamp(60, 86400);
    final collapse = 'vigilance-${draft.departmentCode}-${draft.phenomenon.id}';
    try {
      await _api.projects.messages.send(
        fcm.SendMessageRequest(
          message: fcm.Message(
            token: delivery.pushToken,
            notification: fcm.Notification(
              title: draft.title,
              body: draft.body,
            ),
            data: <String, String>{
              'type': 'official_weather_alert',
              'source': 'meteofrance',
              'eventId': draft.eventId,
              'alertId': draft.alertId,
              'departmentCode': draft.departmentCode,
              'departmentName': draft.departmentName,
              'phenomenon': draft.phenomenon.name,
              'kind': draft.kind.name,
              if (draft.level case final level?) 'level': level.name,
              if (draft.beginsAt case final beginsAt?)
                'beginsAt': beginsAt.toIso8601String(),
              if (draft.endsAt case final endsAt?)
                'endsAt': endsAt.toIso8601String(),
              'officialUrl': 'https://vigilance.meteofrance.fr/fr',
            },
            android: fcm.AndroidConfig(
              collapseKey: collapse,
              priority: 'HIGH',
              ttl: '${expiration}s',
              notification: fcm.AndroidNotification(
                channelId: 'official_weather_alerts',
                clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                defaultSound: true,
                tag: collapse,
              ),
            ),
            apns: fcm.ApnsConfig(
              headers: <String, String>{
                'apns-priority': '10',
                'apns-expiration':
                    '${draft.expiresAt.millisecondsSinceEpoch ~/ 1000}',
                'apns-collapse-id': collapse,
              },
              payload: const <String, Object?>{
                'aps': <String, Object?>{
                  'sound': 'default',
                  'interruption-level': 'time-sensitive',
                },
              },
            ),
          ),
        ),
        _project,
      );
      return VigilancePushOutcome.sent;
    } on fcm.DetailedApiRequestError catch (error) {
      final diagnostic = error.jsonResponse.toString().toUpperCase();
      if (diagnostic.contains('UNREGISTERED') ||
          diagnostic.contains('SENDER_ID_MISMATCH')) {
        return VigilancePushOutcome.invalidToken;
      }
      if (<int>{408, 429, 500, 502, 503, 504}.contains(error.status)) {
        return VigilancePushOutcome.transientFailure;
      }
      return VigilancePushOutcome.permanentFailure;
    } on http.ClientException {
      return VigilancePushOutcome.transientFailure;
    } on SocketException {
      return VigilancePushOutcome.transientFailure;
    } on Object {
      return VigilancePushOutcome.transientFailure;
    }
  }
}
