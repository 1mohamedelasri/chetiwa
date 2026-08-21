final class RateLimitDecision {
  const RateLimitDecision({
    required this.allowed,
    required this.limit,
    required this.remaining,
    required this.retryAfter,
  });

  final bool allowed;
  final int limit;
  final int remaining;
  final Duration retryAfter;
}

final class RequestRateLimiter {
  RequestRateLimiter({
    this.limit = 120,
    this.window = const Duration(minutes: 1),
    this.maxKeys = 10000,
  }) : assert(limit > 0),
       assert(maxKeys > 0);

  final int limit;
  final Duration window;
  final int maxKeys;
  final Map<String, _RateBucket> _buckets = {};

  RateLimitDecision evaluate(String key, DateTime now) {
    final instant = now.toUtc();
    var bucket = _buckets.remove(key);
    if (bucket == null || instant.difference(bucket.startedAt) >= window) {
      bucket = _RateBucket(startedAt: instant, count: 0);
    }
    bucket.count++;
    _buckets[key] = bucket;
    while (_buckets.length > maxKeys) {
      _buckets.remove(_buckets.keys.first);
    }

    final allowed = bucket.count <= limit;
    final elapsed = instant.difference(bucket.startedAt);
    final retryAfter = elapsed >= window ? Duration.zero : window - elapsed;
    return RateLimitDecision(
      allowed: allowed,
      limit: limit,
      remaining: allowed ? limit - bucket.count : 0,
      retryAfter: retryAfter,
    );
  }
}

final class _RateBucket {
  _RateBucket({required this.startedAt, required this.count});

  final DateTime startedAt;
  int count;
}
