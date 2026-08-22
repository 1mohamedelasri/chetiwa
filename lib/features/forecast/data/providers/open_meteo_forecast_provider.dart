import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/api_config.dart';
import '../../../../core/location/coordinates.dart';
import '../../../../core/weather/weather_data_health.dart';

final class OpenMeteoForecastProvider {
  const OpenMeteoForecastProvider(this._client);

  final http.Client _client;

  /// AROME gives France a genuine 15-minute, short-range model forecast.
  /// It is still a model forecast, never presented as observed radar.
  bool usesMeteoFranceNowcast(Coordinates coordinates) =>
      coordinates.latitude >= 41 &&
      coordinates.latitude <= 52 &&
      coordinates.longitude >= -5.8 &&
      coordinates.longitude <= 10;

  String providerNameFor(Coordinates coordinates) =>
      usesMeteoFranceNowcast(coordinates)
      ? 'Météo-France AROME via Open-Meteo'
      : 'Open-Meteo';

  Future<Map<String, dynamic>> fetch(Coordinates coordinates) async {
    final query = <String, String>{
      'latitude': coordinates.latitude.toString(),
      'longitude': coordinates.longitude.toString(),
      'current': 'temperature_2m,weather_code,precipitation,wind_speed_10m',
      'minutely_15': 'precipitation,temperature_2m,wind_speed_10m',
      'hourly':
          'temperature_2m,weather_code,precipitation_probability,precipitation,wind_speed_10m',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
      'forecast_minutely_15': '96',
      // Match the two-hour RainViewer observation window so the compact rain
      // profile under the map shares the radar timeline's real timestamps.
      'past_minutely_15': '8',
      'forecast_days': '10',
      'timezone': 'auto',
      if (ApiConfig.openMeteoApiKey.isNotEmpty)
        'apikey': ApiConfig.openMeteoApiKey,
    };
    final path = usesMeteoFranceNowcast(coordinates)
        ? '/v1/meteofrance'
        : '/v1/forecast';
    final uri = Uri.https(ApiConfig.openMeteoHost, path, query);
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
              'Réponse Open-Meteo invalide',
            );
          }
          return decoded;
        }
        final error = WeatherDataException(
          WeatherDataIssue.providerUnavailable,
          'Open-Meteo HTTP ${response.statusCode}',
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
      'Open-Meteo inaccessible après 3 tentatives: $lastError',
    );
  }
}
