import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

final class RadarTileMetricsSnapshot {
  const RadarTileMetricsSnapshot({
    required this.cacheHits,
    required this.cacheMisses,
    required this.downloadedBytes,
    required this.downloadedTiles,
    required this.sessionTiles,
  });

  final int cacheHits;
  final int cacheMisses;
  final int downloadedBytes;
  final int downloadedTiles;
  final int sessionTiles;

  double get cacheHitRate {
    final total = cacheHits + cacheMisses;
    return total == 0 ? 0 : cacheHits / total;
  }
}

final class RadarTileMetrics {
  final Set<String> _sessionTiles = <String>{};
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _downloadedBytes = 0;
  int _downloadedTiles = 0;

  void beginSession() => _sessionTiles.clear();

  void recordCacheLookup(String url, {required bool hit}) {
    if (hit) {
      _cacheHits++;
    } else {
      _cacheMisses++;
    }
    _sessionTiles.add(url);
  }

  void recordDownload(String url, int bytes) {
    _downloadedTiles++;
    _downloadedBytes += bytes;
    _sessionTiles.add(url);
  }

  RadarTileMetricsSnapshot snapshot() => RadarTileMetricsSnapshot(
    cacheHits: _cacheHits,
    cacheMisses: _cacheMisses,
    downloadedBytes: _downloadedBytes,
    downloadedTiles: _downloadedTiles,
    sessionTiles: _sessionTiles.length,
  );
}

/// Chetiwa's single tile cache for a radar session.
///
/// flutter_map supplies the memory cache and cancellable request lifecycle;
/// its built-in provider supplies the native disk cache and LRU size reducer.
/// This wrapper keeps those behaviours in one place and records anonymous
/// cache/cost metrics without storing coordinates.
final class RadarTileCache {
  static const _cacheSchemaVersion = 'v3';
  static const _maxProviderZoom = 10;
  static const _smokeTestEnabled = bool.fromEnvironment(
    'CHETIWA_RADAR_SMOKE_TEST',
  );

  /// Removes only Chetiwa's regenerable Radar tile cache before a smoke run.
  /// Normal builds cannot invoke the deletion because the compile-time gate is
  /// false.
  static Future<bool> clearDiskCacheForSmokeTest() async {
    if (!_smokeTestEnabled) return false;
    final directory = Directory(
      '${Directory.systemTemp.path}/chetiwa-radar-tiles-$_cacheSchemaVersion',
    );
    if (await directory.exists()) await directory.delete(recursive: true);
    return true;
  }

  RadarTileCache._({http.Client? client})
    : this._withClient(
        client ?? http.Client(),
        _RadarSmokeController(enabled: _smokeTestEnabled),
      );

  RadarTileCache._withClient(http.Client delegate, this._smokeController)
    : metrics = RadarTileMetrics(),
      _client = _RadarSmokeClient(delegate, _smokeController),
      _disk = BuiltInMapCachingProvider.getOrCreateInstance(
        // A versioned, app-specific directory prevents old responses (such
        // as an HTML error body cached as a tile) from surviving an upgrade.
        cacheDirectory:
            '${Directory.systemTemp.path}/chetiwa-radar-tiles-$_cacheSchemaVersion',
        maxCacheSize: 128 * 1024 * 1024,
        overrideFreshAge: const Duration(hours: 6),
      ) {
    tileProvider = NetworkTileProvider(
      abortObsoleteRequests: true,
      httpClient: _client,
      cachingProvider: _instrumentedDisk,
      // A CDN error page is never a valid radar image. Do not pass its body to
      // Android's image decoder; silently retry/skip it instead.
      attemptDecodeOfHttpErrorResponses: false,
      silenceExceptions: true,
    );
  }

  static final RadarTileCache shared = RadarTileCache._();

  final http.Client _client;
  final BuiltInMapCachingProvider _disk;
  final _RadarSmokeController _smokeController;
  final RadarTileMetrics metrics;
  final ValueNotifier<int> readyTileCount = ValueNotifier<int>(0);
  ValueListenable<int> get simulatedFailureCount =>
      _smokeController.failureCount;
  late final NetworkTileProvider tileProvider;
  late final MapCachingProvider _instrumentedDisk = _MetricsCachingProvider(
    delegate: _disk,
    metrics: metrics,
    onValidTile: () => readyTileCount.value++,
    smokeController: _smokeController,
  );
  final Map<String, Future<bool>> _prefetches = <String, Future<bool>>{};
  var _prefetchGeneration = 0;

  void beginSession() {
    metrics.beginSession();
    readyTileCount.value = 0;
    _smokeController.resetFailures();
  }

  /// Arms one HTTP 502 for the physical-device smoke test. It is a no-op in
  /// normal builds and therefore cannot alter production traffic accidentally.
  bool simulateNext502ForSmokeTest() => _smokeController.arm();

  /// Performs a smoke-only origin probe through the same guarded HTTP client
  /// as visible tiles. This makes 502 recovery deterministic without treating
  /// a legitimate pan-buffer cache hit as a failed network request.
  Future<bool> fetchTileForSmokeTest(String url) async {
    if (!_smokeTestEnabled) return false;
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200 &&
          isSupportedImageBytes(response.bodyBytes);
    } on Object {
      return false;
    }
  }

  /// Invalidates speculative work for a viewport that is no longer visible.
  /// HTTP package requests cannot be interrupted after they are sent, so the
  /// bounded in-flight batch may finish; no later batch is started.
  void cancelPrefetch() => _prefetchGeneration++;

  Future<int> prefetchNextFrames({
    required MapCamera camera,
    required Iterable<String> frameTemplates,
    int maxFrames = 1,
    int maxTiles = 8,
    bool completeOnFirstReady = false,
  }) async {
    final generation = ++_prefetchGeneration;
    final templates = frameTemplates.take(maxFrames).toList(growable: false);
    if (templates.isEmpty) return 0;
    final urls = TileViewport.visibleTileUrls(
      camera,
      templates,
      margin: 1,
      maxTiles: maxTiles,
      maxZoom: _maxProviderZoom,
    );
    // Two speculative requests are enough to make animation responsive while
    // leaving connection/origin capacity for the current visible TileLayer.
    var readyTiles = 0;
    for (var index = 0; index < urls.length; index += 2) {
      if (generation != _prefetchGeneration) return 0;
      final end = math.min(index + 2, urls.length);
      final operations = urls.sublist(index, end).map(_prefetchOne).toList();
      if (completeOnFirstReady && await firstReady(operations)) {
        return generation == _prefetchGeneration ? 1 : 0;
      }
      final results = completeOnFirstReady
          ? const <bool>[]
          : await Future.wait(operations, eagerError: false);
      readyTiles += results.where((ready) => ready).length;
    }
    return generation == _prefetchGeneration ? readyTiles : 0;
  }

  /// Resolves as soon as one operation succeeds. Slow siblings deliberately
  /// continue warming the disk cache without delaying the visible repaint.
  @visibleForTesting
  static Future<bool> firstReady(Iterable<Future<bool>> operations) {
    final pending = operations.toList(growable: false);
    if (pending.isEmpty) return Future<bool>.value(false);
    final completer = Completer<bool>();
    var remaining = pending.length;
    for (final operation in pending) {
      operation
          .then((ready) {
            if (ready && !completer.isCompleted) completer.complete(true);
          }, onError: (_, _) {})
          .whenComplete(() {
            remaining--;
            if (remaining == 0 && !completer.isCompleted) {
              completer.complete(false);
            }
          });
    }
    return completer.future;
  }

  Future<bool> _prefetchOne(String url) {
    final existing = _prefetches[url];
    if (existing != null) return existing;
    final operation = _downloadAndCache(url);
    _prefetches[url] = operation;
    operation.whenComplete(() => _prefetches.remove(url));
    return operation;
  }

  Future<bool> _downloadAndCache(String url) async {
    final cached = await _disk.getTile(url);
    if (cached != null &&
        !cached.metadata.isStale &&
        isSupportedImageBytes(cached.bytes)) {
      metrics.recordCacheLookup(url, hit: true);
      return true;
    }
    metrics.recordCacheLookup(url, hit: false);
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 ||
          !isSupportedImageBytes(response.bodyBytes)) {
        return false;
      }
      final bytes = Uint8List.fromList(response.bodyBytes);
      await _disk.putTile(
        url: url,
        metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().add(const Duration(hours: 6)),
          lastModified: null,
          etag: response.headers['etag'],
        ),
        bytes: bytes,
      );
      metrics.recordDownload(url, bytes.length);
      return true;
    } on Object {
      // The visible TileLayer remains the source of truth if prefetch fails.
      return false;
    }
  }

  /// Reject non-image responses before Flutter sends them to Android's image
  /// decoder. Platform decoding still validates the full image afterwards.
  static bool isSupportedImageBytes(List<int> bytes) {
    if (bytes.length < 12) return false;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final webp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return png || jpeg || webp;
  }
}

final class _MetricsCachingProvider implements MapCachingProvider {
  const _MetricsCachingProvider({
    required this.delegate,
    required this.metrics,
    required this.onValidTile,
    required this.smokeController,
  });

  final MapCachingProvider delegate;
  final RadarTileMetrics metrics;
  final VoidCallback onValidTile;
  final _RadarSmokeController smokeController;

  @override
  bool get isSupported => delegate.isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    if (smokeController.shouldBypassCache) return null;
    final value = await delegate.getTile(url);
    if (value != null && !RadarTileCache.isSupportedImageBytes(value.bytes)) {
      metrics.recordCacheLookup(url, hit: false);
      return null;
    }
    metrics.recordCacheLookup(
      url,
      hit: value != null && !value.metadata.isStale,
    );
    if (value != null) onValidTile();
    return value;
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    if (bytes != null && !RadarTileCache.isSupportedImageBytes(bytes)) return;
    await delegate.putTile(url: url, metadata: metadata, bytes: bytes);
    if (bytes != null) {
      metrics.recordDownload(url, bytes.length);
      onValidTile();
    }
  }
}

final class _RadarSmokeController {
  _RadarSmokeController({required this.enabled});

  final bool enabled;
  final ValueNotifier<int> failureCount = ValueNotifier<int>(0);
  bool _armed = false;

  bool get shouldBypassCache => enabled && _armed;

  bool arm() {
    if (!enabled) return false;
    _armed = true;
    return true;
  }

  bool consumeFailure() {
    if (!_armed) return false;
    _armed = false;
    failureCount.value++;
    return true;
  }

  void resetFailures() {
    _armed = false;
    failureCount.value = 0;
  }
}

final class _RadarSmokeClient extends http.BaseClient {
  _RadarSmokeClient(this._delegate, this._controller);

  final http.Client _delegate;
  final _RadarSmokeController _controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_controller.consumeFailure()) {
      return Future<http.StreamedResponse>.value(
        http.StreamedResponse(
          const Stream<List<int>>.empty(),
          502,
          request: request,
          headers: const <String, String>{'content-type': 'text/plain'},
          reasonPhrase: 'Radar smoke-test failure',
        ),
      );
    }
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}

final class TileViewport {
  const TileViewport._();

  static List<String> visibleTileUrls(
    MapCamera camera,
    Iterable<String> templates, {
    int margin = 1,
    int maxTiles = 24,
    int? maxZoom,
  }) {
    final zoom = maxZoom == null
        ? camera.zoom.floor()
        : camera.zoom.floor().clamp(0, maxZoom).toInt();
    final world = 1 << zoom;
    final bounds = camera.visibleBounds;
    final west = _longitudeToX(bounds.west, world);
    final east = _longitudeToX(bounds.east, world);
    final north = _latitudeToY(bounds.north, world);
    final south = _latitudeToY(bounds.south, world);
    final minX = west.floor() - margin;
    final maxX = east.ceil() + margin;
    final minY = (north.floor() - margin).clamp(0, world - 1);
    final maxY = (south.ceil() + margin).clamp(0, world - 1);
    final centerX = _longitudeToX(camera.center.longitude, world);
    final centerY = _latitudeToY(camera.center.latitude, world);
    final coordinates = <({int x, int y})>[];
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        coordinates.add((x: x, y: y));
      }
    }
    // Load the tile under the crosshair first, then expand outwards. The old
    // top-left scan could spend the complete first batch on pan-buffer tiles
    // that were not actually visible to the user.
    coordinates.sort((a, b) {
      final aDistance =
          math.pow(a.x + 0.5 - centerX, 2) + math.pow(a.y + 0.5 - centerY, 2);
      final bDistance =
          math.pow(b.x + 0.5 - centerX, 2) + math.pow(b.y + 0.5 - centerY, 2);
      return aDistance.compareTo(bDistance);
    });
    final tiles = <String>[];
    for (final template in templates) {
      for (final coordinate in coordinates) {
        if (tiles.length >= maxTiles) break;
        final wrappedX = ((coordinate.x % world) + world) % world;
        tiles.add(
          template
              .replaceAll('{z}', '$zoom')
              .replaceAll('{x}', '$wrappedX')
              .replaceAll('{y}', '${coordinate.y}'),
        );
      }
      if (tiles.length >= maxTiles) break;
    }
    return tiles.toSet().toList(growable: false);
  }

  static double _longitudeToX(double longitude, int world) =>
      ((longitude + 180) / 360) * world;

  static double _latitudeToY(double latitude, int world) {
    final clamped = latitude.clamp(-85.05112878, 85.05112878);
    final radians = clamped * 3.141592653589793 / 180;
    return (1 -
            (math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi)) /
        2 *
        world;
  }
}
