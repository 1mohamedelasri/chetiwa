import 'package:flutter/widgets.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app/app.dart';
import 'app/di/chetiwa_dependencies.dart';
import 'features/monetization/application/app_feature_flag_controller.dart';
import 'features/forecast/application/weather_section_cubit.dart';

const _screen = String.fromEnvironment('STORE_SCREEN', defaultValue: 'graph');

String get _initialLocation => switch (_screen) {
  'alerts' => '/alerts',
  'settings' => '/settings',
  _ => '/weather',
};

WeatherSection get _initialWeatherSection => switch (_screen) {
  'radar' => WeatherSection.radar,
  'forecast' => WeatherSection.forecast,
  _ => WeatherSection.graph,
};

/// Deterministic, offline-only entry point for Store screenshots.
/// It is never referenced by production builds.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(
    ChetiwaApp(
      dependencies: ChetiwaDependencies.fixture(
        featureFlags: const AppFeatureFlags.disabled(),
        storeScreenshot: true,
      ),
      initialLocation: _initialLocation,
      initialWeatherSection: _initialWeatherSection,
    ),
  );
}
