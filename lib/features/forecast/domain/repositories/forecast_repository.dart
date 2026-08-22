import '../../../../core/location/coordinates.dart';
import '../entities/forecast.dart';

final class CachedForecast {
  const CachedForecast({required this.forecast, required this.cachedAt});

  final Forecast forecast;
  final DateTime cachedAt;

  bool isStaleAt(DateTime nowUtc) =>
      nowUtc.toUtc().difference(cachedAt.toUtc()) > const Duration(minutes: 30);
}

abstract interface class ForecastRepository {
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates);

  Future<Forecast> getForecast(Coordinates coordinates);
}
