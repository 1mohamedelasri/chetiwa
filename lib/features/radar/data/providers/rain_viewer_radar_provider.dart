import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/weather/weather_data_health.dart';

final class RainViewerRadarProvider {
  const RainViewerRadarProvider(this._client);

  final http.Client _client;

  Future<Map<String, dynamic>> fetchMetadata() async {
    final uri = Uri.parse(ApiConfig.radarMetadataUrl);
    Object? lastError;
    var terminalIssue = WeatherDataIssue.offline;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
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
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    throw WeatherDataException(
      terminalIssue,
      'Radar inaccessible après 3 tentatives: $lastError',
    );
  }
}
