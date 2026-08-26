import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);
  final clock = FixedWeatherClock(now);
  late Forecast forecast;

  setUpAll(() async {
    forecast = await FixtureForecastDataSource(clock: clock).load();
  });

  testWidgets('Free shows a locked and clearly labelled model segment', (
    tester,
  ) async {
    final frames = <RadarFrame>[
      RadarFrame(
        time: now,
        progress: 0,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: now.add(const Duration(minutes: 60)),
        progress: 1,
        kind: WeatherDataKind.radarNowcast,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RadarTimeline(
            state: RadarReady(
              frames: frames,
              selectedIndex: 0,
              coordinates: Coordinates.paris,
            ),
            forecast: forecast,
            snapshot: ForecastSnapshotBuilder.build(
              forecast: forecast,
              nowUtc: now,
            ),
            playbackProgress: const AlwaysStoppedAnimation<double>(0),
            modelForecastLocked: true,
          ),
        ),
      ),
    );

    expect(find.text('PRÉVISION ÉTENDUE · 10 MIN'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('radar-point-profile-unavailable-premium-locked'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Premium displays model frames without calling them radar', (
    tester,
  ) async {
    final modelTime = now.add(const Duration(minutes: 90));
    final frames = <RadarFrame>[
      RadarFrame(
        time: now,
        progress: 0,
        kind: WeatherDataKind.radarObservation,
      ),
      RadarFrame(
        time: now.add(const Duration(minutes: 60)),
        progress: 0.5,
        kind: WeatherDataKind.radarNowcast,
      ),
      RadarFrame(
        time: modelTime,
        progress: 1,
        kind: WeatherDataKind.modelForecast,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RadarTimeline(
            state: RadarReady(
              frames: frames,
              selectedIndex: 2,
              coordinates: Coordinates.paris,
            ),
            forecast: forecast,
            snapshot: ForecastSnapshotBuilder.build(
              forecast: forecast,
              nowUtc: now,
            ),
            playbackProgress: const AlwaysStoppedAnimation<double>(0),
          ),
        ),
      ),
    );

    expect(find.textContaining('prévision étendue Chetiwa+'), findsOneWidget);
    expect(find.textContaining('prévision radar'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('radar-point-profile-unavailable-premium-open'),
      ),
      findsOneWidget,
    );
  });
}
