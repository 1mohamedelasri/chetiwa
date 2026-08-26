import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/location/coordinates.dart';
import '../../../../core/weather/weather_data_health.dart';

final class RainViewerRadarProvider {
  const RainViewerRadarProvider(this._client);

  final http.Client _client;

  /// Reads LibreWXR's point nowcast through its stateless MCP HTTP endpoint.
  /// This is the authoritative value used to reconcile the map with the
  /// two-hour graph at the exact selected coordinate.
  Future<List<Map<String, dynamic>>> fetchPointNowcast(
    Coordinates coordinates,
  ) async {
    final metadataUri = Uri.parse(ApiConfig.radarMetadataUrl);
    final uri = metadataUri.replace(path: '/mcp/', query: null);
    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json, text/event-stream',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'tools/call',
              'params': {
                'name': 'get_precip_nowcast',
                'arguments': {
                  'lat': coordinates.latitude,
                  'lon': coordinates.longitude,
                  'minutes': 120,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];

      // FastMCP responds as a one-message SSE stream. Be tolerant of a plain
      // JSON response too so a transport upgrade does not break the app.
      final payload = response.body
          .split('\n')
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.startsWith('data:'),
            orElse: () => response.body.trim(),
          );
      final jsonText = payload.startsWith('data:')
          ? payload.substring(5).trim()
          : payload;
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return const [];
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) return const [];
      final structured = result['structuredContent'];
      if (structured is! Map<String, dynamic>) return const [];
      return (structured['result'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } on Object {
      // Point sampling enriches radar data but must never make the tile layer
      // unavailable. The model remains the labelled fallback in Graph.
      return const [];
    }
  }

  Future<Map<String, dynamic>> fetchMetadata() async {
    final uri = Uri.parse(ApiConfig.radarMetadataUrl);
    Object? lastError;
    var terminalIssue = WeatherDataIssue.offline;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const WeatherDataException(
              WeatherDataIssue.invalidResponse,
              'Réponse radar invalide',
            );
          }
          return decoded;
        }
        final error = WeatherDataException(
          WeatherDataIssue.providerUnavailable,
          'Radar HTTP ${response.statusCode}',
        );
        if (response.statusCode < 500 && response.statusCode != 429) {
          throw error;
        }
        lastError = error;
        terminalIssue = WeatherDataIssue.providerUnavailable;
      } on TimeoutException catch (error) {
        lastError = error;
        terminalIssue = WeatherDataIssue.offline;
      } on http.ClientException catch (error) {
        lastError = error;
        terminalIssue = WeatherDataIssue.offline;
      }
      if (attempt < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    throw WeatherDataException(
      terminalIssue,
      'Radar inaccessible après 2 tentatives: $lastError',
    );
  }
}
