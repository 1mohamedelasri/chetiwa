import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'device_alert_store.dart';
import 'vigilance_alert_engine.dart';

/// Reads official European warnings through the public MeteoGate gateway.
///
/// One snapshot is shared by every Chetiwa user. User coordinates are matched
/// against the exact warning polygons in [VigilanceAlertEngine], so provider
/// traffic does not grow with the installation count.
final class MeteoAlarmVigilanceProvider implements VigilanceProvider {
  MeteoAlarmVigilanceProvider({
    required http.Client client,
    required String apiKey,
    Uri? warningsUri,
    DateTime Function()? now,
    this.maximumPages = 10,
    this.maximumConcurrentDownloads = 8,
  }) : _client = client,
       _apiKey = apiKey.trim(),
       _warningsUri =
           warningsUri ??
           Uri.parse(
             'https://api.meteogate.eu/warnings/collections/warnings/locations/ALL',
           ),
       _now = now ?? DateTime.now {
    if (_apiKey.isEmpty) {
      throw StateError('METEOALARM_API_KEY is required');
    }
    if (maximumPages < 1 || maximumConcurrentDownloads < 1) {
      throw ArgumentError(
        'MeteoAlarm pagination and concurrency must be positive',
      );
    }
  }

  final http.Client _client;
  final String _apiKey;
  final Uri _warningsUri;
  final DateTime Function() _now;
  final int maximumPages;
  final int maximumConcurrentDownloads;

  @override
  Future<VigilanceSnapshot> current() async {
    final instant = _now().toUtc();
    final features = await _activeFeatures(instant);
    if (features.isEmpty) {
      return VigilanceSnapshot(
        snapshotId: 'meteoalarm-empty-${instant.toIso8601String()}',
        productAt: instant,
        events: const <VigilanceEvent>[],
      );
    }

    final capCache = <String, Future<Map<String, Object?>?>>{};
    final geometryCache = <String, Future<List<VigilancePolygon>>>{};
    final events = <VigilanceEvent>[];
    for (
      var offset = 0;
      offset < features.length;
      offset += maximumConcurrentDownloads
    ) {
      final end = (offset + maximumConcurrentDownloads).clamp(
        0,
        features.length,
      );
      final batch = await Future.wait(
        features
            .sublist(offset, end)
            .map(
              (feature) => _event(
                feature,
                instant: instant,
                capCache: capCache,
                geometryCache: geometryCache,
              ),
            ),
      );
      events.addAll(batch.whereType<VigilanceEvent>());
    }
    if (events.isEmpty) {
      throw StateError('MeteoAlarm returned warnings that could not be parsed');
    }

    final productAt = features
        .map(_featureProductAt)
        .whereType<DateTime>()
        .fold<DateTime>(
          instant.subtract(const Duration(hours: 23)),
          (latest, candidate) => candidate.isAfter(latest) ? candidate : latest,
        );
    final ids =
        features
            .map(
              (feature) => _map(feature['properties'])['alertId']?.toString(),
            )
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final snapshotId = sha256
        .convert('${productAt.toIso8601String()}|${ids.join('|')}'.codeUnits)
        .toString();
    return VigilanceSnapshot(
      snapshotId: 'meteoalarm-$snapshotId',
      productAt: productAt,
      events: List<VigilanceEvent>.unmodifiable(events),
    );
  }

  Future<List<Map<String, Object?>>> _activeFeatures(DateTime instant) async {
    final from = instant.subtract(const Duration(hours: 23));
    final result = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var page = 1; page <= maximumPages; page += 1) {
      final uri = _warningsUri.replace(
        queryParameters: <String, String>{
          ..._warningsUri.queryParameters,
          'datetime': '${from.toIso8601String()}/${instant.toIso8601String()}',
          'active': instant.toIso8601String(),
          'language': 'fr',
          'page': page.toString(),
        },
      );
      final response = await _client
          .get(
            uri,
            headers: <String, String>{
              HttpHeaders.acceptHeader: 'application/geo+json',
              'apikey': _apiKey,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 204) break;
      if (response.statusCode != 200) {
        throw StateError(
          'MeteoGate warnings API returned ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final pageFeatures = _list(_map(decoded)['features'])
          .whereType<Map>()
          .map((value) => Map<String, Object?>.from(value))
          .toList(growable: false);
      var added = 0;
      for (final feature in pageFeatures) {
        final properties = _map(feature['properties']);
        final identity =
            '${properties['OBJECTID'] ?? feature['id']}|'
            '${properties['alertId']}|${properties['indexArea']}';
        if (seen.add(identity)) {
          result.add(feature);
          added += 1;
        }
      }
      if (pageFeatures.length < 100 || added == 0) break;
    }
    return result;
  }

  Future<VigilanceEvent?> _event(
    Map<String, Object?> feature, {
    required DateTime instant,
    required Map<String, Future<Map<String, Object?>?>> capCache,
    required Map<String, Future<List<VigilancePolygon>>> geometryCache,
  }) async {
    try {
      final properties = _map(feature['properties']);
      if (properties['supersededAt'] != null) return null;
      final links = _list(feature['links']);
      final capUri = _link(links, 'application/json');
      final geometryUri = _link(links, 'application/geo+json');
      if (capUri == null || geometryUri == null) return null;
      final cap = await capCache.putIfAbsent(
        capUri.toString(),
        () => _json(capUri),
      );
      if (cap == null) return null;
      final messageType = cap['msgType']?.toString().toLowerCase();
      final status = cap['status']?.toString().toLowerCase();
      if (messageType == 'cancel' || (status != null && status != 'actual')) {
        return null;
      }
      final polygons = await geometryCache.putIfAbsent(
        geometryUri.toString(),
        () => _geometry(geometryUri),
      );
      if (polygons.isEmpty) return null;

      final info = _selectInfo(cap, properties);
      if (info == null) return null;
      final level = _level(info);
      final phenomenon = _phenomenon(info);
      final beginsAt = _date(info['onset'] ?? info['effective'] ?? cap['sent']);
      final endsAt = _date(info['expires']);
      if (level == null ||
          phenomenon == null ||
          beginsAt == null ||
          endsAt == null ||
          !endsAt.isAfter(beginsAt) ||
          !endsAt.isAfter(instant)) {
        return null;
      }
      return VigilanceEvent(
        phenomenon: phenomenon,
        level: level,
        beginsAt: beginsAt,
        endsAt: endsAt,
        polygons: polygons,
      );
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>?> _json(Uri uri) async {
    if (!_trustedArtifact(uri)) return null;
    final response = await _client
        .get(uri, headers: const <String, String>{'accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  Future<List<VigilancePolygon>> _geometry(Uri uri) async {
    final json = await _json(uri);
    if (json == null) return const <VigilancePolygon>[];
    final geometry = json['type'] == 'Feature' ? _map(json['geometry']) : json;
    return _polygons(geometry);
  }

  static Map<String, Object?>? _selectInfo(
    Map<String, Object?> cap,
    Map<String, Object?> properties,
  ) {
    final infos = _list(cap['info'])
        .whereType<Map>()
        .map((value) => Map<String, Object?>.from(value))
        .toList(growable: false);
    if (infos.isEmpty) return null;
    final requestedIndex = _integer(properties['indexInfo']);
    if (requestedIndex != null &&
        requestedIndex >= 0 &&
        requestedIndex < infos.length) {
      return infos[requestedIndex];
    }
    for (final prefix in const <String>['fr', 'en']) {
      for (final info in infos) {
        if (info['language']?.toString().toLowerCase().startsWith(prefix) ==
            true) {
          return info;
        }
      }
    }
    return infos.first;
  }

  static VigilanceLevel? _level(Map<String, Object?> info) {
    final value = _parameter(info, 'awareness_level');
    final colorId = value == null
        ? null
        : int.tryParse(value.split(';').first.trim());
    if (colorId == null || colorId < 2 || colorId > 4) return null;
    return VigilanceLevel.fromColorId(colorId);
  }

  static VigilancePhenomenon? _phenomenon(Map<String, Object?> info) {
    final value = _parameter(info, 'awareness_type');
    final type = value == null
        ? null
        : int.tryParse(value.split(';').first.trim());
    return switch (type) {
      1 => VigilancePhenomenon.wind,
      2 => VigilancePhenomenon.snowIce,
      3 => VigilancePhenomenon.thunderstorms,
      4 => VigilancePhenomenon.fog,
      5 => VigilancePhenomenon.heatwave,
      6 => VigilancePhenomenon.extremeCold,
      7 || 14 => VigilancePhenomenon.coastalFlooding,
      8 => VigilancePhenomenon.forestFire,
      9 => VigilancePhenomenon.avalanches,
      10 || 13 => VigilancePhenomenon.rainFlood,
      12 => VigilancePhenomenon.floods,
      15 => VigilancePhenomenon.drought,
      _ => null,
    };
  }

  static String? _parameter(Map<String, Object?> info, String name) {
    for (final raw in _list(info['parameter'])) {
      final parameter = _map(raw);
      if (parameter['valueName']?.toString() == name) {
        return parameter['value']?.toString();
      }
    }
    return null;
  }

  static List<VigilancePolygon> _polygons(Map<String, Object?> geometry) {
    final coordinates = _list(geometry['coordinates']);
    return switch (geometry['type']) {
      'Polygon' => [?_polygon(coordinates)],
      'MultiPolygon' =>
        coordinates
            .map((value) => _polygon(_list(value)))
            .whereType<VigilancePolygon>()
            .toList(growable: false),
      _ => const <VigilancePolygon>[],
    };
  }

  static VigilancePolygon? _polygon(List<Object?> coordinates) {
    final rings = coordinates
        .map(_ring)
        .where((ring) => ring.length >= 3)
        .toList(growable: false);
    if (rings.isEmpty) return null;
    return VigilancePolygon(outer: rings.first, holes: rings.skip(1).toList());
  }

  static List<VigilancePoint> _ring(Object? raw) => _list(raw)
      .map(_list)
      .where((coordinate) => coordinate.length >= 2)
      .map(
        (coordinate) => VigilancePoint(
          longitude: (coordinate[0] as num).toDouble(),
          latitude: (coordinate[1] as num).toDouble(),
        ),
      )
      .toList(growable: false);

  static Uri? _link(List<Object?> links, String type) {
    for (final raw in links) {
      final link = _map(raw);
      if (link['type']?.toString() != type) continue;
      final uri = Uri.tryParse(link['href']?.toString() ?? '');
      if (uri != null && _trustedArtifact(uri)) return uri;
    }
    return null;
  }

  static bool _trustedArtifact(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'meteo.fra1.digitaloceanspaces.com' ||
          uri.host == 'api.meteoalarm.org' ||
          uri.host == 'api.meteogate.eu');

  static DateTime? _featureProductAt(Map<String, Object?> feature) =>
      _date(_map(feature['properties'])['hubTime']);

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '')?.toUtc();

  static int? _integer(Object? value) => switch (value) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];
}
