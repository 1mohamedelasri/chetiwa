import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/rain_rate_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));
  final cases =
      <(ReferenceWeatherScenario, WeatherBriefType, RainIntensity, int)>[
        (
          ReferenceWeatherScenario.dry,
          WeatherBriefType.dry,
          RainIntensity.none,
          0,
        ),
        (
          ReferenceWeatherScenario.light,
          WeatherBriefType.raining,
          RainIntensity.light,
          1,
        ),
        (
          ReferenceWeatherScenario.moderate,
          WeatherBriefType.raining,
          RainIntensity.moderate,
          1,
        ),
        (
          ReferenceWeatherScenario.heavy,
          WeatherBriefType.raining,
          RainIntensity.heavy,
          1,
        ),
        (
          ReferenceWeatherScenario.multipleEpisodes,
          WeatherBriefType.multipleEpisodes,
          RainIntensity.moderate,
          2,
        ),
      ];

  for (final item in cases) {
    test('maps the ${item.$1.name} reference scenario consistently', () async {
      final dataSource = FixtureForecastDataSource(
        fixtureName: item.$1.fixtureName,
        clock: clock,
      );
      final forecast = await dataSource.load();

      expect(forecast.locationName, 'Paris, France');
      expect(forecast.brief.type, item.$2);
      expect(forecast.brief.intensity, item.$3);
      expect(forecast.windows, hasLength(item.$4));
      expect(
        forecast.points.map(
          (point) => RainRateScale.intensityFor(point.rateMmPerHour),
        ),
        forecast.points.map((point) => point.intensity),
      );
    });
  }

  test('uses stable intensity and visual thresholds', () {
    expect(RainRateScale.intensityFor(0.049), RainIntensity.none);
    expect(RainRateScale.intensityFor(0.05), RainIntensity.light);
    expect(RainRateScale.intensityFor(0.499), RainIntensity.light);
    expect(RainRateScale.intensityFor(0.5), RainIntensity.moderate);
    expect(RainRateScale.intensityFor(3.999), RainIntensity.moderate);
    expect(RainRateScale.intensityFor(4), RainIntensity.heavy);

    expect(RainRateScale.normalized(0.49), lessThan(0.24));
    expect(RainRateScale.normalized(0.5), closeTo(0.24, 0.001));
    expect(RainRateScale.normalized(3.9), lessThan(0.56));
    expect(RainRateScale.normalized(4), closeTo(0.56, 0.001));
    expect(RainRateScale.normalized(12), 1);
  });
}
