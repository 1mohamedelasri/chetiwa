import '../../../../core/location/coordinates.dart';
import '../../domain/entities/forecast.dart';
import '../../domain/repositories/forecast_repository.dart';
import '../datasources/fixture_forecast_data_source.dart';

final class FixtureForecastRepository implements ForecastRepository {
  const FixtureForecastRepository(this._dataSource);

  final FixtureForecastDataSource _dataSource;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      null;

  @override
  Future<Forecast> getForecast(Coordinates coordinates) => _dataSource.load();
}
