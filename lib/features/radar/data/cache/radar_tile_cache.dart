import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
    hit ? _cacheHits++ : _cacheMisses++;
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

final class _RadarDownloadWaiter {
  const _RadarDownloadWaiter({
    required this.generation,
    required this.completer,
  });

  final int? generation;
  final Completer<bool> completer;
}

final class _RadarCoordinateFallback {
  const _RadarCoordinateFallback({required this.bytes, required this.savedAt});

  final Uint8List bytes;
  final DateTime savedAt;
}

/// Shared LibreWXR cache used by Google Maps tile overlays on Android and iOS.
///
/// The Google basemap is rendered by the native SDK. Radar bytes still flow
/// through Chetiwa so a CDN error page can never reach a platform image decoder.
final class RadarTileCache {
  static const _cacheSchemaVersion = 'v7-crisp-bands-persistent-radar';
  static const _maxNativeZoom = 10;
  static const _maxDisplayZoom = 14;
  static const _maxConcurrentDownloads = 6;
  static const _maxConcurrentRenders = 2;
  static const _maxDiskBytes = 128 * 1024 * 1024;
  static const _maxMemoryBytes = 16 * 1024 * 1024;
  static const _maxCoordinateFallbacks = 64;
  static const _coordinateFallbackAge = Duration(minutes: 30);
  static const _freshAge = Duration(hours: 6);
  // A genuinely cold LibreWXR coordinate can take 5-7 seconds to build once
  // before the server/CDN caches it. Returning NO_TILE after 2.5 seconds made
  // Google Maps remember a blank tile while the origin finished useful work
  // in the background. Keep the request asynchronous, but allow that first
  // bounded render to complete so the preparation screen can hand off a
  // complete viewport instead of a patchwork.
  static const _tileRequestTimeout = Duration(seconds: 8);
  static const _retryDelay = Duration(milliseconds: 120);
  static const _smokeTestEnabled = bool.fromEnvironment(
    'CHETIWA_RADAR_SMOKE_TEST',
  );

  static Future<bool> clearDiskCacheForSmokeTest() async {
    if (!_smokeTestEnabled) return false;
    final directory = await _persistentDirectory();
    if (await directory.exists()) await directory.delete(recursive: true);
    return true;
  }

  RadarTileCache._({http.Client? client, Directory? directory})
    : this._withClient(
        client ?? http.Client(),
        _RadarSmokeController(enabled: _smokeTestEnabled),
        directory == null
            ? _persistentDirectory()
            : Future<Directory>.value(directory),
      );

  RadarTileCache._withClient(
    http.Client delegate,
    this._smokeController,
    this._directoryFuture,
  ) : metrics = RadarTileMetrics(),
      _client = _RadarSmokeClient(delegate, _smokeController) {
    unawaited(_prepareDirectory());
  }

  @visibleForTesting
  factory RadarTileCache.forTesting({
    required http.Client client,
    required Directory directory,
  }) => RadarTileCache._(client: client, directory: directory);

  static final RadarTileCache shared = RadarTileCache._();

  static Future<Directory> _persistentDirectory() async {
    try {
      final parent = await getApplicationCacheDirectory();
      return Directory(
        '${parent.path}/chetiwa-radar-tiles-$_cacheSchemaVersion',
      );
    } on Object {
      // Unit tests and very early platform bootstrap may not expose the path
      // provider yet. The fallback remains functional, while real Android and
      // iOS builds use their persistent application cache directory.
      return Directory(
        '${Directory.systemTemp.path}/chetiwa-radar-tiles-$_cacheSchemaVersion',
      );
    }
  }

  final http.Client _client;
  final Future<Directory> _directoryFuture;
  final _RadarSmokeController _smokeController;
  final RadarTileMetrics metrics;
  final ValueNotifier<int> readyTileCount = ValueNotifier<int>(0);
  final ValueNotifier<int> successfulTileResponseCount = ValueNotifier<int>(0);
  ValueListenable<int> get simulatedFailureCount =>
      _smokeController.failureCount;

  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};
  final Map<String, Future<Uint8List?>> _derivedInFlight =
      <String, Future<Uint8List?>>{};
  final Queue<_RadarDownloadWaiter> _downloadWaiters =
      Queue<_RadarDownloadWaiter>();
  final Queue<Completer<void>> _renderWaiters = Queue<Completer<void>>();
  final LinkedHashSet<RadarTileCoordinate> _recentCoordinates =
      LinkedHashSet<RadarTileCoordinate>();
  final LinkedHashMap<String, _RadarCoordinateFallback> _coordinateFallbacks =
      LinkedHashMap<String, _RadarCoordinateFallback>();
  final Set<String> _readySessionTiles = <String>{};
  var _memoryBytes = 0;
  var _activeDownloads = 0;
  var _activeRenders = 0;
  var _prefetchGeneration = 0;
  var _viewportGeneration = 0;

  /// Coordinates requested by the native map for the settled viewport.
  ///
  /// Playback uses this to require a complete current/next-frame buffer. A
  /// single successful tile is not enough: swapping on that signal was the
  /// source of the small-echo-then-large-patch jump on real phones.
  int get recentCoordinateCount => _recentCoordinates.length;

  void beginSession() {
    metrics.beginSession();
    _readySessionTiles.clear();
    _recentCoordinates.clear();
    _coordinateFallbacks.clear();
    readyTileCount.value = 0;
    successfulTileResponseCount.value = 0;
    _smokeController.resetFailures();
    beginViewport();
  }

  /// Invalidates queued work from the previous camera viewport. Downloads
  /// already on the wire may finish and populate the cache, but they cannot
  /// retry or keep newer visible requests trapped behind an obsolete queue.
  int beginViewport({bool preserveRecentCoordinates = false}) {
    _viewportGeneration++;
    cancelPrefetch();
    if (!preserveRecentCoordinates) _recentCoordinates.clear();
    while (_downloadWaiters.isNotEmpty) {
      _downloadWaiters.removeFirst().completer.complete(false);
    }
    return _viewportGeneration;
  }

  RadarGoogleTileProvider providerFor(String template) =>
      RadarGoogleTileProvider(cache: this, template: template);

  bool simulateNext502ForSmokeTest({String? url}) =>
      _smokeController.arm(url: url);

  Future<bool> fetchTileForSmokeTest(String url) async {
    if (!_smokeTestEnabled) return false;
    return await _getBytes(url, forceNetwork: true, requestGeneration: null) !=
        null;
  }

  void cancelPrefetch() => _prefetchGeneration++;

  /// Warms the same geographic tiles the native SDK most recently requested.
  /// This avoids speculative rings and keeps origin traffic bounded on pans.
  Future<int> prefetchNextFrames({
    required Iterable<String> frameTemplates,
    int maxFrames = 1,
    int maxTiles = 6,
    int maxConcurrent = 2,
    bool completeOnFirstReady = false,
  }) async {
    assert(maxConcurrent > 0 && maxConcurrent <= _maxConcurrentDownloads);
    final generation = ++_prefetchGeneration;
    final viewportGeneration = _viewportGeneration;
    final coordinates = _recentCoordinates.toList(growable: false).reversed;
    final templates = frameTemplates.take(maxFrames).toList(growable: false);
    final requests = <({String template, RadarTileCoordinate coordinate})>[];
    // Interleave frames so the current frame cannot consume the whole budget
    // before the next animation frame gets warmed.
    for (final coordinate in coordinates) {
      for (final template in templates) {
        if (requests.length >= maxTiles) break;
        requests.add((template: template, coordinate: coordinate));
      }
      if (requests.length >= maxTiles) break;
    }
    if (requests.isEmpty) return 0;
    var readyTiles = 0;
    // Camera-idle recovery may use four operations once the current viewport
    // is already presented; ordinary speculative work keeps the conservative
    // default of two so native Google Maps requests retain priority.
    for (var index = 0; index < requests.length; index += maxConcurrent) {
      if (generation != _prefetchGeneration) return 0;
      final end = math.min(index + maxConcurrent, requests.length);
      final operations = requests
          .sublist(index, end)
          .map((request) async {
            if (generation != _prefetchGeneration) return false;
            return await _tileBytes(
                  request.template,
                  request.coordinate,
                  recordReady: false,
                  requestGeneration: viewportGeneration,
                ) !=
                null;
          })
          .toList(growable: false);
      if (completeOnFirstReady) {
        if (await firstReady(operations)) {
          return generation == _prefetchGeneration ? 1 : 0;
        }
      } else {
        final values = await Future.wait(operations, eagerError: false);
        readyTiles += values.where((value) => value).length;
      }
    }
    return generation == _prefetchGeneration ? readyTiles : 0;
  }

  /// Makes the selected frame immediately available to a second native tile
  /// overlay before the UI starts a cross-fade. Unlike speculative prefetch,
  /// this foreground operation is not cancelled when the following frame is
  /// scheduled: it represents what the user is about to see.
  Future<int> prepareVisibleFrame(
    String frameTemplate, {
    int maxTiles = 12,
    bool completeOnFirstReady = false,
  }) async {
    final viewportGeneration = _viewportGeneration;
    final coordinates = _recentCoordinates
        .toList(growable: false)
        .reversed
        .take(maxTiles)
        .toList(growable: false);
    if (coordinates.isEmpty) return 0;

    var readyTiles = 0;
    // Four foreground operations are enough to fill a typical phone viewport
    // quickly while leaving two download slots for native Google Maps calls.
    for (var index = 0; index < coordinates.length; index += 4) {
      final end = math.min(index + 4, coordinates.length);
      final operations = coordinates
          .sublist(index, end)
          .map(
            (coordinate) async =>
                await _tileBytes(
                  frameTemplate,
                  coordinate,
                  recordReady: false,
                  requestGeneration: viewportGeneration,
                ) !=
                null,
          )
          .toList(growable: false);
      if (completeOnFirstReady) {
        return await firstReady(operations) ? 1 : 0;
      }
      final values = await Future.wait(operations, eagerError: false);
      readyTiles += values.where((value) => value).length;
    }
    return readyTiles;
  }

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

  void _recordRequested(RadarTileCoordinate coordinate) {
    _recentCoordinates.remove(coordinate);
    _recentCoordinates.add(coordinate);
    while (_recentCoordinates.length > 16) {
      _recentCoordinates.remove(_recentCoordinates.first);
    }
  }

  Future<Uint8List?> _tileBytes(
    String template,
    RadarTileCoordinate requestedCoordinate, {
    bool recordReady = true,
    int? requestGeneration,
  }) async {
    if (requestedCoordinate.zoom > _maxDisplayZoom) return null;
    final effectiveGeneration = requestGeneration ?? _viewportGeneration;
    if (effectiveGeneration != _viewportGeneration) return null;
    _recordRequested(requestedCoordinate);
    final sourceCoordinate = requestedCoordinate.ancestorAt(_maxNativeZoom);
    final sourceUrl = sourceCoordinate.resolve(template);
    final fallbackKey = _coordinateFallbackKey(sourceCoordinate);
    final fallback = _takeCoordinateFallback(fallbackKey);
    final sourceBytes = await _getBytes(
      sourceUrl,
      fallbackAvailable: fallback != null,
      requestGeneration: effectiveGeneration,
    );
    final effectiveSourceBytes = sourceBytes ?? fallback?.bytes;
    if (effectiveSourceBytes == null) return null;
    if (sourceBytes != null) {
      _putCoordinateFallback(fallbackKey, sourceBytes);
    }

    final bytes = requestedCoordinate.zoom <= _maxNativeZoom
        ? effectiveSourceBytes
        : await _overzoomBytes(
            sourceBytes: effectiveSourceBytes,
            sourceUrl: sourceUrl,
            sourceCoordinate: sourceCoordinate,
            requestedCoordinate: requestedCoordinate,
          );
    final readyKey =
        '${requestedCoordinate.zoom}/'
        '${requestedCoordinate.x}/${requestedCoordinate.y}:$sourceUrl';
    if (recordReady && bytes != null) {
      successfulTileResponseCount.value++;
      if (_readySessionTiles.add(readyKey)) readyTileCount.value++;
    }
    return bytes;
  }

  Future<Uint8List?> _overzoomBytes({
    required Uint8List sourceBytes,
    required String sourceUrl,
    required RadarTileCoordinate sourceCoordinate,
    required RadarTileCoordinate requestedCoordinate,
  }) {
    final cacheKey =
        'overzoom:${requestedCoordinate.zoom}/'
        '${requestedCoordinate.x}/${requestedCoordinate.y}:$sourceUrl';
    final cached = _takeMemory(cacheKey);
    if (cached != null) return Future<Uint8List?>.value(cached);
    final existing = _derivedInFlight[cacheKey];
    if (existing != null) return existing;
    final operation = () async {
      await _acquireRenderSlot();
      try {
        final bytes = await _renderOverzoomTile(
          sourceBytes: sourceBytes,
          sourceCoordinate: sourceCoordinate,
          requestedCoordinate: requestedCoordinate,
        );
        if (bytes != null) _putMemory(cacheKey, bytes);
        return bytes;
      } finally {
        _releaseRenderSlot();
      }
    }();
    _derivedInFlight[cacheKey] = operation;
    operation.whenComplete(() => _derivedInFlight.remove(cacheKey));
    return operation;
  }

  static Future<Uint8List?> _renderOverzoomTile({
    required Uint8List sourceBytes,
    required RadarTileCoordinate sourceCoordinate,
    required RadarTileCoordinate requestedCoordinate,
  }) async {
    ui.Codec? codec;
    ui.Image? sourceImage;
    ui.Image? outputImage;
    ui.Picture? picture;
    try {
      final delta = requestedCoordinate.zoom - sourceCoordinate.zoom;
      if (delta <= 0) return sourceBytes;
      final scale = 1 << delta;
      final childX = requestedCoordinate.x - (sourceCoordinate.x << delta);
      final childY = requestedCoordinate.y - (sourceCoordinate.y << delta);
      if (childX < 0 || childX >= scale || childY < 0 || childY >= scale) {
        return null;
      }

      codec = await ui.instantiateImageCodec(sourceBytes);
      final frame = await codec.getNextFrame();
      sourceImage = frame.image;
      final sourceWidth = sourceImage.width / scale;
      final sourceHeight = sourceImage.height / scale;
      if (sourceWidth < 1 || sourceHeight < 1) return null;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        sourceImage,
        ui.Rect.fromLTWH(
          childX * sourceWidth,
          childY * sourceHeight,
          sourceWidth,
          sourceHeight,
        ),
        const ui.Rect.fromLTWH(0, 0, 256, 256),
        // Radar is categorical raster data. Nearest-neighbour preserves echo
        // boundaries and avoids inventing blended intensity at tile edges.
        ui.Paint()..filterQuality = ui.FilterQuality.none,
      );
      picture = recorder.endRecording();
      outputImage = await picture.toImage(256, 256);
      final data = await outputImage.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } on Object {
      return null;
    } finally {
      outputImage?.dispose();
      sourceImage?.dispose();
      picture?.dispose();
      codec?.dispose();
    }
  }

  Future<Uint8List?> _getBytes(
    String url, {
    bool forceNetwork = false,
    bool fallbackAvailable = false,
    required int? requestGeneration,
  }) {
    final inFlightKey = '${requestGeneration ?? 'smoke'}:$url';
    final existing = _inFlight[inFlightKey];
    if (existing != null) return existing;
    final operation = _loadBytes(
      url,
      forceNetwork: forceNetwork,
      fallbackAvailable: fallbackAvailable,
      requestGeneration: requestGeneration,
    );
    _inFlight[inFlightKey] = operation;
    operation.whenComplete(() => _inFlight.remove(inFlightKey));
    return operation;
  }

  Future<Uint8List?> _loadBytes(
    String url, {
    required bool forceNetwork,
    required bool fallbackAvailable,
    required int? requestGeneration,
  }) async {
    if (!forceNetwork && !_smokeController.shouldBypassCacheFor(url)) {
      final memory = _takeMemory(url);
      if (memory != null) {
        metrics.recordCacheLookup(url, hit: true);
        return memory;
      }
      final disk = await _readDisk(url);
      if (disk != null) {
        metrics.recordCacheLookup(url, hit: true);
        _putMemory(url, disk);
        return disk;
      }
    }
    metrics.recordCacheLookup(url, hit: false);
    if (!await _acquireDownloadSlot(requestGeneration)) return null;
    try {
      // Once this exact geographic tile has a previously presented image,
      // one bounded refresh attempt is enough. A second long retry used to
      // freeze the complete animation whenever LibreWXR regenerated frames.
      // The caller can safely preserve the last good echo and try the next
      // timestamp without ever returning a blank native Google tile.
      final attempts =
          (forceNetwork && _smokeController.enabled) || fallbackAvailable
          ? 1
          : 2;
      for (var attempt = 0; attempt < attempts; attempt++) {
        try {
          final response = await _client
              .get(Uri.parse(url))
              .timeout(
                fallbackAvailable
                    ? const Duration(seconds: 4)
                    : _tileRequestTimeout,
              );
          if (response.statusCode == 200) {
            if (isSupportedImageBytes(response.bodyBytes)) {
              final bytes = Uint8List.fromList(response.bodyBytes);
              _putMemory(url, bytes);
              metrics.recordDownload(url, bytes.length);
              unawaited(_writeDisk(url, bytes));
              return bytes;
            }
            // Some edge proxies return an HTML error page with HTTP 200. Treat
            // it as transient once, but never hand those bytes to the decoder.
          } else if (!_isRetryableStatus(response.statusCode)) {
            return null;
          }
        } on TimeoutException {
          // Retry once below. A missing tile must never block the map UI.
        } on SocketException {
          // Mobile networks frequently change while the user is panning.
        } on http.ClientException {
          // Retry one transient transport failure, then return NO_TILE.
        }
        if (requestGeneration != null &&
            requestGeneration != _viewportGeneration) {
          return null;
        }
        if (attempt + 1 < attempts) await Future<void>.delayed(_retryDelay);
      }
      return null;
    } on Object {
      return null;
    } finally {
      _releaseDownloadSlot();
    }
  }

  static bool _isRetryableStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode >= 500;

  Future<bool> _acquireDownloadSlot(int? requestGeneration) async {
    if (requestGeneration != null && requestGeneration != _viewportGeneration) {
      return false;
    }
    if (_activeDownloads < _maxConcurrentDownloads) {
      _activeDownloads++;
      return true;
    }
    final waiter = _RadarDownloadWaiter(
      generation: requestGeneration,
      completer: Completer<bool>(),
    );
    _downloadWaiters.addLast(waiter);
    return waiter.completer.future;
  }

  void _releaseDownloadSlot() {
    while (_downloadWaiters.isNotEmpty) {
      final waiter = _downloadWaiters.removeFirst();
      if (waiter.generation != null &&
          waiter.generation != _viewportGeneration) {
        waiter.completer.complete(false);
        continue;
      }
      // Transfer this active slot directly to the next current request.
      waiter.completer.complete(true);
      return;
    }
    _activeDownloads--;
  }

  Future<void> _acquireRenderSlot() async {
    if (_activeRenders < _maxConcurrentRenders) {
      _activeRenders++;
      return;
    }
    final waiter = Completer<void>();
    _renderWaiters.addLast(waiter);
    await waiter.future;
  }

  void _releaseRenderSlot() {
    if (_renderWaiters.isNotEmpty) {
      _renderWaiters.removeFirst().complete();
      return;
    }
    _activeRenders--;
  }

  Uint8List? _takeMemory(String url) {
    final value = _memory.remove(url);
    if (value != null) _memory[url] = value;
    return value;
  }

  void _putMemory(String url, Uint8List bytes) {
    final previous = _memory.remove(url);
    if (previous != null) _memoryBytes -= previous.length;
    _memory[url] = bytes;
    _memoryBytes += bytes.length;
    while (_memoryBytes > _maxMemoryBytes && _memory.isNotEmpty) {
      final first = _memory.remove(_memory.keys.first);
      if (first != null) _memoryBytes -= first.length;
    }
  }

  static String _coordinateFallbackKey(RadarTileCoordinate coordinate) =>
      '${coordinate.zoom}/${coordinate.x}/${coordinate.y}';

  _RadarCoordinateFallback? _takeCoordinateFallback(String key) {
    final fallback = _coordinateFallbacks.remove(key);
    if (fallback == null) return null;
    if (DateTime.now().difference(fallback.savedAt) > _coordinateFallbackAge) {
      return null;
    }
    _coordinateFallbacks[key] = fallback;
    return fallback;
  }

  void _putCoordinateFallback(String key, Uint8List bytes) {
    _coordinateFallbacks.remove(key);
    _coordinateFallbacks[key] = _RadarCoordinateFallback(
      bytes: bytes,
      savedAt: DateTime.now(),
    );
    while (_coordinateFallbacks.length > _maxCoordinateFallbacks) {
      _coordinateFallbacks.remove(_coordinateFallbacks.keys.first);
    }
  }

  Future<void> _prepareDirectory() async {
    final directory = await _directoryFuture;
    await directory.create(recursive: true);
    await _trimDiskCache();
  }

  File _fileFor(Directory directory, String url) =>
      File('${directory.path}/${_stableHash(url)}.tile');

  Future<Uint8List?> _readDisk(String url) async {
    try {
      final directory = await _directoryFuture;
      final file = _fileFor(directory, url);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          DateTime.now().difference(stat.modified) > _freshAge) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (!isSupportedImageBytes(bytes)) {
        unawaited(file.delete());
        return null;
      }
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeDisk(String url, Uint8List bytes) async {
    try {
      final directory = await _directoryFuture;
      await directory.create(recursive: true);
      final file = _fileFor(directory, url);
      final temporary = File(
        '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      await temporary.writeAsBytes(bytes, flush: false);
      await temporary.rename(file.path);
    } on FileSystemException {
      // Cache writes are opportunistic and must never block visible Radar.
    }
  }

  Future<void> _trimDiskCache() async {
    try {
      final directory = await _directoryFuture;
      final files = await directory
          .list()
          .where((entry) => entry is File && entry.path.endsWith('.tile'))
          .cast<File>()
          .toList();
      final entries = <({File file, FileStat stat})>[];
      var total = 0;
      for (final file in files) {
        final stat = await file.stat();
        total += stat.size;
        entries.add((file: file, stat: stat));
      }
      if (total <= _maxDiskBytes) return;
      entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      for (final entry in entries) {
        if (total <= _maxDiskBytes * 0.85) break;
        await entry.file.delete();
        total -= entry.stat.size;
      }
    } on FileSystemException {
      // The operating system may evict its cache concurrently.
    }
  }

  static String _stableHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

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

final class RadarGoogleTileProvider implements TileProvider {
  RadarGoogleTileProvider({required this.cache, required this.template});

  final RadarTileCache cache;
  final String template;
  final ValueNotifier<int> presentationRevision = ValueNotifier<int>(0);
  final Set<RadarTileCoordinate> _presentationRequests =
      <RadarTileCoordinate>{};
  final Set<RadarTileCoordinate> _presentationSuccesses =
      <RadarTileCoordinate>{};
  var _presentationGeneration = 0;

  int get requestedCoordinateCount => _presentationRequests.length;
  int get successfulCoordinateCount => _presentationSuccesses.length;
  int get presentedCoordinateCount =>
      _presentationRequests.where(_presentationSuccesses.contains).length;
  bool get hasCompletePresentation =>
      _presentationRequests.isNotEmpty &&
      presentedCoordinateCount == _presentationRequests.length;

  bool hasPresentationCoverage({
    required int minimumCoordinates,
    double minimumRatio = 1,
  }) {
    if (_presentationRequests.length < minimumCoordinates) return false;
    final presented = presentedCoordinateCount;
    return presented >= minimumCoordinates &&
        presented / _presentationRequests.length >= minimumRatio;
  }

  /// Starts a new native repaint observation window without invalidating the
  /// shared byte cache. A subsequent `clearTileCache` should repopulate this
  /// provider from memory and lets the UI wait for the exact visible viewport
  /// instead of a global "one tile arrived" signal.
  void resetPresentationTracking() {
    _presentationGeneration++;
    _presentationRequests.clear();
    _presentationSuccesses.clear();
    presentationRevision.value++;
  }

  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    if (zoom == null || zoom < 0) return TileProvider.noTile;
    final world = 1 << zoom;
    if (y < 0 || y >= world) return TileProvider.noTile;
    final coordinate = RadarTileCoordinate(
      x: ((x % world) + world) % world,
      y: y,
      zoom: zoom,
    );
    final presentationGeneration = _presentationGeneration;
    if (_presentationRequests.add(coordinate)) {
      presentationRevision.value++;
    }
    final bytes = await cache._tileBytes(template, coordinate);
    if (bytes == null) return TileProvider.noTile;
    // A native request may finish after a camera move reset the observation
    // window. Never let that old completion masquerade as a tile presented in
    // the new viewport; it was the source of equal request/success counts with
    // zero actual overlap on iOS.
    if (presentationGeneration != _presentationGeneration) {
      return Tile(256, 256, bytes);
    }
    if (_presentationSuccesses.add(coordinate)) {
      presentationRevision.value++;
    }
    return Tile(256, 256, bytes);
  }
}

@immutable
final class RadarTileCoordinate {
  const RadarTileCoordinate({
    required this.x,
    required this.y,
    required this.zoom,
  });

  final int x;
  final int y;
  final int zoom;

  RadarTileCoordinate ancestorAt(int maxZoom) {
    if (zoom <= maxZoom) return this;
    final delta = zoom - maxZoom;
    return RadarTileCoordinate(x: x >> delta, y: y >> delta, zoom: maxZoom);
  }

  String resolve(String template) => template
      .replaceAll('{z}', '$zoom')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  @override
  bool operator ==(Object other) =>
      other is RadarTileCoordinate &&
      x == other.x &&
      y == other.y &&
      zoom == other.zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);
}

/// Platform-independent viewport math retained for unit tests and diagnostics.
final class TileViewport {
  const TileViewport._();

  static List<String> visibleTileUrls({
    required double centerLatitude,
    required double centerLongitude,
    required double north,
    required double south,
    required double east,
    required double west,
    required double zoom,
    required Iterable<String> templates,
    int margin = 1,
    int maxTiles = 24,
    int maxZoom = 10,
  }) {
    final tileZoom = zoom.floor().clamp(0, maxZoom).toInt();
    final world = 1 << tileZoom;
    final minX = _longitudeToX(west, world).floor() - margin;
    final maxX = _longitudeToX(east, world).ceil() + margin;
    final minY = (_latitudeToY(north, world).floor() - margin).clamp(
      0,
      world - 1,
    );
    final maxY = (_latitudeToY(south, world).ceil() + margin).clamp(
      0,
      world - 1,
    );
    final centerX = _longitudeToX(centerLongitude, world);
    final centerY = _latitudeToY(centerLatitude, world);
    final coordinates = <RadarTileCoordinate>[];
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        coordinates.add(
          RadarTileCoordinate(
            x: ((x % world) + world) % world,
            y: y,
            zoom: tileZoom,
          ),
        );
      }
    }
    coordinates.sort((a, b) {
      final ad =
          math.pow(a.x + 0.5 - centerX, 2) + math.pow(a.y + 0.5 - centerY, 2);
      final bd =
          math.pow(b.x + 0.5 - centerX, 2) + math.pow(b.y + 0.5 - centerY, 2);
      return ad.compareTo(bd);
    });
    final urls = <String>[];
    for (final template in templates) {
      for (final coordinate in coordinates) {
        if (urls.length >= maxTiles) break;
        urls.add(coordinate.resolve(template));
      }
      if (urls.length >= maxTiles) break;
    }
    return urls.toSet().toList(growable: false);
  }

  static double _longitudeToX(double longitude, int world) =>
      ((longitude + 180) / 360) * world;

  static double _latitudeToY(double latitude, int world) {
    final clamped = latitude.clamp(-85.05112878, 85.05112878);
    final radians = clamped * math.pi / 180;
    return (1 -
            (math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi)) /
        2 *
        world;
  }
}

final class _RadarSmokeController {
  _RadarSmokeController({required this.enabled});

  final bool enabled;
  final ValueNotifier<int> failureCount = ValueNotifier<int>(0);
  bool _armed = false;
  String? _targetUrl;

  bool shouldBypassCacheFor(String url) =>
      enabled && _armed && (_targetUrl == null || _targetUrl == url);

  bool arm({String? url}) {
    if (!enabled) return false;
    _armed = true;
    _targetUrl = url;
    return true;
  }

  bool consumeFailure(String url) {
    if (!_armed || (_targetUrl != null && _targetUrl != url)) return false;
    _armed = false;
    _targetUrl = null;
    failureCount.value++;
    return true;
  }

  void resetFailures() {
    _armed = false;
    _targetUrl = null;
    failureCount.value = 0;
  }
}

final class _RadarSmokeClient extends http.BaseClient {
  _RadarSmokeClient(this._delegate, this._controller);

  final http.Client _delegate;
  final _RadarSmokeController _controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_controller.consumeFailure(request.url.toString())) {
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
