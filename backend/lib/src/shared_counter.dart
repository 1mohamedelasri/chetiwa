import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Counter boundary used by the quota guard. The in-memory implementation is
/// safe for local and one-instance staging only; production must configure the
/// HTTP implementation backed by a shared Redis/Firestore counter service.
abstract interface class SharedCounter {
  Future<int> increment(String key, {required Duration ttl, int amount = 1});
}

final class InMemorySharedCounter implements SharedCounter {
  final Map<String, _Counter> _counters = {};

  @override
  Future<int> increment(
    String key, {
    required Duration ttl,
    int amount = 1,
  }) async {
    final now = DateTime.timestamp();
    final previous = _counters[key];
    final counter = previous == null || !now.isBefore(previous.expiresAt)
        ? _Counter(expiresAt: now.add(ttl))
        : previous;
    counter.value += amount;
    _counters[key] = counter;
    return counter.value;
  }
}

/// Calls a small internal counter service. This keeps Cloud Run instances
/// stateless while the counter service provides atomic INCR + TTL semantics.
final class HttpSharedCounter implements SharedCounter {
  HttpSharedCounter({required Uri endpoint, http.Client? client})
    : _endpoint = endpoint,
      _client = client ?? http.Client();

  final Uri _endpoint;
  final http.Client _client;

  @override
  Future<int> increment(
    String key, {
    required Duration ttl,
    int amount = 1,
  }) async {
    final response = await _client.post(
      _endpoint,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(<String, Object>{
        'key': key,
        'ttlSeconds': ttl.inSeconds,
        'amount': amount,
      }),
    );
    if (response.statusCode != 200) {
      throw StateError('Shared counter returned HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['value'] is! int) {
      throw const FormatException('Invalid shared counter response');
    }
    return body['value'] as int;
  }
}

final class _Counter {
  _Counter({required this.expiresAt});
  final DateTime expiresAt;
  int value = 0;
}
