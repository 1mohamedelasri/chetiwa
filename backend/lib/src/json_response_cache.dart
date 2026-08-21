final class CachePolicy {
  const CachePolicy({required this.freshFor, required this.staleIfErrorFor});

  final Duration freshFor;
  final Duration staleIfErrorFor;
}

final class CachedJsonResponse {
  const CachedJsonResponse({
    required this.body,
    required this.etag,
    required this.storedAt,
  });

  final String body;
  final String etag;
  final DateTime storedAt;

  bool isFresh(DateTime now, CachePolicy policy) =>
      now.difference(storedAt) <= policy.freshFor;

  bool canServeStale(DateTime now, CachePolicy policy) =>
      now.difference(storedAt) <= policy.staleIfErrorFor;
}

final class JsonResponseCache {
  JsonResponseCache({this.maxEntries = 1000})
    : assert(maxEntries > 0, 'maxEntries must be positive');

  final int maxEntries;
  final Map<String, CachedJsonResponse> _entries = {};

  CachedJsonResponse? read(String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void write(String key, CachedJsonResponse value) {
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = value;
  }

  void clear() => _entries.clear();
}
