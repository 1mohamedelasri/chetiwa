import 'dart:typed_data';

final class TileCachePolicy {
  const TileCachePolicy({
    this.freshFor = const Duration(hours: 6),
    this.staleIfErrorFor = const Duration(days: 2),
  });

  final Duration freshFor;
  final Duration staleIfErrorFor;
}

final class CachedTileResponse {
  const CachedTileResponse({
    required this.bytes,
    required this.etag,
    required this.storedAt,
  });

  final Uint8List bytes;
  final String etag;
  final DateTime storedAt;

  bool isFresh(DateTime now, TileCachePolicy policy) =>
      now.difference(storedAt) <= policy.freshFor;

  bool canServeStale(DateTime now, TileCachePolicy policy) =>
      now.difference(storedAt) <= policy.staleIfErrorFor;
}

final class TileResponseCache {
  TileResponseCache({this.maxEntries = 2048, this.maxBytes = 128 * 1024 * 1024})
    : assert(maxEntries > 0),
      assert(maxBytes > 0);

  final int maxEntries;
  final int maxBytes;
  final Map<String, CachedTileResponse> _entries = {};
  var _bytes = 0;

  CachedTileResponse? read(String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void write(String key, CachedTileResponse value) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.bytes.length;
    while (_entries.length >= maxEntries ||
        _bytes + value.bytes.length > maxBytes) {
      if (_entries.isEmpty) break;
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey)!;
      _bytes -= oldest.bytes.length;
    }
    _entries[key] = value;
    _bytes += value.bytes.length;
  }

  int get entryCount => _entries.length;
  int get bytes => _bytes;

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}
