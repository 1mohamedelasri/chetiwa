import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/forecast/domain/services/radar_nowcast_alignment.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Graph uses LibreWXR point samples inside the nowcast window', () async {
    final now = DateTime.utc(2026, 8, 20, 12);
    final forecast = await FixtureForecastDataSource(
      fixtureName: 'dry',
      clock: FixedWeatherClock(now),
    ).load();
    final radarTime = now.add(const Duration(minutes: 10));

    final aligned = alignForecastWithRadarNowcast(forecast, [
      RadarFrame(
        time: radarTime,
        progress: 1,
        kind: WeatherDataKind.radarNowcast,
        pointRainRateMmPerHour: 5,
        pointRainSource: 'radar',
      ),
    ], now);

    expect(aligned.rainPointAt(radarTime)?.intensity, RainIntensity.heavy);
    expect(aligned.providerName, contains('LibreWXR nowcast'));
    final snapshot = ForecastSnapshotBuilder.build(
      forecast: aligned,
      nowUtc: now,
    );
    expect(snapshot.brief.type, WeatherBriefType.imminent);
    expect(snapshot.brief.rainStart, radarTime);
  });

  test('Graph keeps the model when point sampling is unavailable', () async {
    final now = DateTime.utc(2026, 8, 20, 12);
    final forecast = await FixtureForecastDataSource(
      fixtureName: 'dry',
      clock: FixedWeatherClock(now),
    ).load();

    final aligned = alignForecastWithRadarNowcast(forecast, [
      RadarFrame(
        time: now.add(const Duration(minutes: 10)),
        progress: 1,
        kind: WeatherDataKind.radarNowcast,
      ),
    ], now);

    expect(identical(aligned, forecast), isTrue);
  });

  test('Graph resumes model data after the LibreWXR nowcast window', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final modelTailTime = now.add(const Duration(minutes: 90));
    final forecast = Forecast(
      locationName: 'Paris',
      updatedAt: now,
      temperatureCelsius: 20,
      windKph: 5,
      brief: const WeatherBrief(
        type: WeatherBriefType.dry,
        intensity: RainIntensity.none,
        headline: 'Dry',
        detail: 'Dry',
      ),
      points: [
        RainPoint(
          time: now.add(const Duration(minutes: 30)),
          rateMmPerHour: 1,
          intensity: RainIntensity.light,
        ),
        RainPoint(
          time: modelTailTime,
          rateMmPerHour: 3,
          intensity: RainIntensity.moderate,
        ),
      ],
      windows: const [],
    );

    final aligned = alignForecastWithRadarNowcast(forecast, [
      RadarFrame(
        time: now.add(const Duration(minutes: 60)),
        progress: 1,
        kind: WeatherDataKind.radarNowcast,
        pointRainRateMmPerHour: 2,
      ),
    ], now);

    expect(aligned.rainPointAt(modelTailTime)?.rateMmPerHour, 3);
    expect(aligned.points.last.time, modelTailTime);
  });
}
