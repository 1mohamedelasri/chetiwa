import '../../core/location/coordinates.dart';
import '../../core/location/location_repository.dart';
import '../../core/weather/weather_data_health.dart';
import '../../features/forecast/domain/entities/forecast.dart';
import '../../features/forecast/domain/repositories/forecast_repository.dart';
import '../../features/radar/domain/entities/radar_frame.dart';
import '../../features/radar/domain/repositories/radar_repository.dart';

final class DevelopmentFallbackForecastRepository
    implements ForecastRepository {
  const DevelopmentFallbackForecastRepository(this.primary, this.fallback);

  final ForecastRepository primary;
  final ForecastRepository fallback;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      await primary.getCachedForecast(coordinates) ??
      await fallback.getCachedForecast(coordinates);

  @override
  Future<Forecast> getForecast(Coordinates coordinates) async {
    try {
      return await primary.getForecast(coordinates);
    } on WeatherDataException {
      return fallback.getForecast(coordinates);
    }
  }
}

final class DevelopmentFallbackRadarRepository implements RadarRepository {
  const DevelopmentFallbackRadarRepository(this.primary, this.fallback);

  final RadarRepository primary;
  final RadarRepository fallback;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      await primary.getCachedFrames(coordinates) ??
      await fallback.getCachedFrames(coordinates);

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async {
    try {
      return await primary.getFrames(coordinates);
    } on WeatherDataException {
      return fallback.getFrames(coordinates);
    }
  }
}

final class DevelopmentFallbackLocationRepository
    implements LocationRepository {
  const DevelopmentFallbackLocationRepository(this.primary, this.fallback);

  final LocationRepository primary;
  final LocationRepository fallback;

  @override
  Future<List<ChetiwaLocation>> search(String query) async {
    try {
      return await primary.search(query);
    } on LocationException {
      return fallback.search(query);
    }
  }

  @override
  Future<ChetiwaLocation> getCurrentLocation() => primary.getCurrentLocation();

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) async {
    try {
      return await primary.resolveCoordinates(coordinates);
    } on LocationException {
      return fallback.resolveCoordinates(coordinates);
    }
  }

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() =>
      primary.getRecentLocations();

  @override
  Future<void> remember(ChetiwaLocation location) => primary.remember(location);

  @override
  Future<ChetiwaLocation?> getMainLocation() => primary.getMainLocation();

  @override
  Future<void> setMainLocation(ChetiwaLocation location) =>
      primary.setMainLocation(location);

  @override
  Future<void> clearMainLocation() => primary.clearMainLocation();

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) =>
      primary.removeRecentLocation(location);

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) =>
      primary.openLocationRecovery(action);
}
