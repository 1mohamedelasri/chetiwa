import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
  RadarTileCache._({http.Client? client})
    : metrics = RadarTileMetrics(),
      _client = client ?? http.Client(),
      _disk = BuiltInMapCachingProvider.getOrCreateInstance(
        // A dedicated cache directory avoids making tile caching depend on a
        // path_provider plugin call during widget tests and still lives on
        // the platform's temporary disk cache on iOS/Android.
        cacheDirectory: Directory.systemTemp.path,
        maxCacheSize: 64 * 1024 * 1024,
        overrideFreshAge: const Duration(hours: 6),
      ) {
    tileProvider = NetworkTileProvider(
      abortObsoleteRequests: true,
      httpClient: _client,
      cachingProvider: _instrumentedDisk,
      silenceExceptions: true,
    );
  }

  static final RadarTileCache shared = RadarTileCache._();

  final http.Client _client;
  final BuiltInMapCachingProvider _disk;
  final RadarTileMetrics metrics;
  late final NetworkTileProvider tileProvider;
  late final MapCachingProvider _instrumentedDisk = _MetricsCachingProvider(
    delegate: _disk,
    metrics: metrics,
  );
  final Map<String, Future<void>> _prefetches = <String, Future<void>>{};

  void beginSession() => metrics.beginSession();

  Future<void> prefetchNextFrames({
    required MapCamera camera,
    required Iterable<String> frameTemplates,
    int maxFrames = 2,
    int maxTiles = 24,
  }) async {
    final templates = frameTemplates.take(maxFrames).toList(growable: false);
    if (templates.isEmpty) return;
    final urls = TileViewport.visibleTileUrls(
      camera,
      templates,
      margin: 1,
      maxTiles: maxTiles,
    );
    await Future.wait(urls.map(_prefetchOne), eagerError: false);
  }

  Future<void> _prefetchOne(String url) {
    final existing = _prefetches[url];
    if (existing != null) return existing;
    final operation = _downloadAndCache(url);
    _prefetches[url] = operation;
    operation.whenComplete(() => _prefetches.remove(url));
    return operation;
  }

  Future<void> _downloadAndCache(String url) async {
    final cached = await _disk.getTile(url);
    if (cached != null && !cached.metadata.isStale) {
      metrics.recordCacheLookup(url, hit: true);
      return;
    }
    metrics.recordCacheLookup(url, hit: false);
    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
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
    } on Object {
      // The visible TileLayer remains the source of truth if prefetch fails.
    }
  }
}

final class _MetricsCachingProvider implements MapCachingProvider {
  const _MetricsCachingProvider({
    required this.delegate,
    required this.metrics,
  });

  final MapCachingProvider delegate;
  final RadarTileMetrics metrics;

  @override
  bool get isSupported => delegate.isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    final value = await delegate.getTile(url);
    metrics.recordCacheLookup(
      url,
      hit: value != null && !value.metadata.isStale,
    );
    return value;
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    await delegate.putTile(url: url, metadata: metadata, bytes: bytes);
    if (bytes != null) metrics.recordDownload(url, bytes.length);
  }
}

final class TileViewport {
  const TileViewport._();

  static List<String> visibleTileUrls(
    MapCamera camera,
    Iterable<String> templates, {
    int margin = 1,
    int maxTiles = 24,
  }) {
    final zoom = camera.zoom.floor();
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
    final tiles = <String>[];
    for (final template in templates) {
      for (var y = minY; y <= maxY && tiles.length < maxTiles; y++) {
        for (var x = minX; x <= maxX && tiles.length < maxTiles; x++) {
          final wrappedX = ((x % world) + world) % world;
          tiles.add(
            template
                .replaceAll('{z}', '$zoom')
                .replaceAll('{x}', '$wrappedX')
                .replaceAll('{y}', '$y'),
          );
        }
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
