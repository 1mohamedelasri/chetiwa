import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/location/fixture_location_repository.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/data/repositories/fixture_forecast_repository.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  final fixedClock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));

  setUpAll(() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  });

  tearDownAll(() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  });

  for (final scenario in ReferenceWeatherScenario.values) {
    testWidgets('captures ${scenario.name} on $_platformName', (tester) async {
      final dependencies = ChetiwaDependencies.testing(
        weatherClock: fixedClock,
        forecastRepository: FixtureForecastRepository(
          FixtureForecastDataSource(
            fixtureName: scenario.fixtureName,
            clock: fixedClock,
          ),
        ),
        radarRepository: FixtureRadarRepository(clock: fixedClock),
        locationRepository: const FixtureLocationRepository(),
      );

      await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
      await _waitFor(tester, find.byKey(const Key('rain-chart')));
      if (defaultTargetPlatform == TargetPlatform.android) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await binding.takeScreenshot('${_platformName}_${scenario.name}_graph');

      await tester.tap(find.text('Radar'));
      await _waitFor(tester, find.byKey(const Key('radar-local-time')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await binding.takeScreenshot('${_platformName}_${scenario.name}_radar');

      await tester.tap(find.text('Prévisions'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('PRÉVISIONS HEURE PAR HEURE'), findsOneWidget);
      await binding.takeScreenshot(
        '${_platformName}_${scenario.name}_forecast',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

String get _platformName => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'android',
  TargetPlatform.iOS => 'ios',
  _ => defaultTargetPlatform.name,
};

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}
