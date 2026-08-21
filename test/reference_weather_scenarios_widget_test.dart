import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/application/graph_horizon_cubit.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/graph_pane.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 8, 20, 12);
  final clock = FixedWeatherClock(now);
  final expectedIntensity = <ReferenceWeatherScenario, RainIntensity>{
    ReferenceWeatherScenario.dry: RainIntensity.none,
    ReferenceWeatherScenario.light: RainIntensity.light,
    ReferenceWeatherScenario.moderate: RainIntensity.moderate,
    ReferenceWeatherScenario.heavy: RainIntensity.heavy,
    ReferenceWeatherScenario.multipleEpisodes: RainIntensity.moderate,
  };

  for (final scenario in ReferenceWeatherScenario.values) {
    testWidgets('Graph and Radar render the ${scenario.name} scenario', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final forecast = await FixtureForecastDataSource(
        fixtureName: scenario.fixtureName,
        clock: clock,
      ).load();
      final snapshot = ForecastSnapshotBuilder.build(
        forecast: forecast,
        nowUtc: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) => GraphHorizonCubit(),
              child: GraphPane(forecast: forecast, snapshot: snapshot),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('rain-chart')), findsOneWidget);
      expect(
        find.byKey(
          Key('rain-chart-intensity-${expectedIntensity[scenario]!.name}'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final selectedTime = scenario == ReferenceWeatherScenario.multipleEpisodes
          ? now.add(const Duration(minutes: 25))
          : now;
      final selectedIntensity = forecast.rainPointAt(selectedTime)!.intensity;
      final rainRate = forecast.rainPointAt(selectedTime)!.rateMmPerHour;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 480,
              child: RadarIntensityOverlay(progress: 1, rainRate: rainRate),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(Key('fallback-radar-${selectedIntensity.name}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
