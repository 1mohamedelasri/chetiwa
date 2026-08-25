import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/core/notifications/rain_alert_navigation_controller.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/data/repositories/fixture_forecast_repository.dart';
import 'package:chetiwa/features/forecast/application/weather_section_cubit.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens on Graph and switches to Radar without changing route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = ChetiwaDependencies.fixture();
    await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
    await _loadFixture(tester);
    expect(dependencies.usageQuotaController.radarSessions.used, 0);

    expect(
      (tester.getCenter(find.text('Chetiwa')).dy -
              tester.getCenter(find.text('Paris, France')).dy)
          .abs(),
      lessThan(4),
    );
    expect(find.byKey(const Key('open-settings-navigation')), findsOneWidget);
    expect(find.byKey(const Key('rain-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('rain-chart-cursor-now')), findsOneWidget);
    // Source details remain available in Sources & Licences; the primary
    // Graph header stays focused on the actual rain answer.
    expect(find.byKey(const Key('graph-provenance-label')), findsNothing);
    expect(find.text('2H'), findsOneWidget);
    expect(find.text('Graph'), findsOneWidget);
    expect(find.byKey(const Key('adaptive-ad-banner-slot')), findsOneWidget);
    expect(
      find.byKey(const Key('selected-navigation-indicator')),
      findsOneWidget,
    );
    // Radar stays mounted offstage so its current viewport is warm before the
    // first navigation tap.
    expect(
      find.byKey(const ValueKey('radar'), skipOffstage: false),
      findsOneWidget,
    );
    final radarBloc = tester
        .element(find.byKey(const ValueKey('graph')))
        .read<RadarBloc>();
    expect((radarBloc.state as RadarReady).isPlaying, isFalse);

    await tester.drag(
      find.byKey(const Key('rain-chart')),
      const Offset(100, 0),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('rain-chart-cursor-selected')),
      findsOneWidget,
    );

    await tester.tap(find.text('Radar'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(dependencies.usageQuotaController.radarSessions.used, 1);
    await tester.tap(find.text('Radar'));
    await tester.pump();
    expect(dependencies.usageQuotaController.radarSessions.used, 1);

    // Radar starts automatically when its surface becomes visible. Real tile
    // builds additionally wait for the first decoded PNG before autoplay.
    final section = tester
        .element(find.byKey(const ValueKey('radar'), skipOffstage: false))
        .read<WeatherSectionCubit>();
    expect(section.state, WeatherSection.radar);
    expect((radarBloc.state as RadarReady).isPlaying, isTrue);
    expect(find.byKey(const Key('radar-city-pin')), findsOneWidget);
    expect(find.byKey(const Key('radar-time-ruler')), findsOneWidget);
    expect(find.byKey(const Key('radar-reset-button')), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
    expect(find.textContaining('dernière observation'), findsOneWidget);

    await tester.tap(find.byKey(const Key('radar-layers-button')));
    await tester.pumpAndSettle();
    expect(find.text('Couches de la carte'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Satellite'), findsNothing);
    expect(find.text('Radar de précipitations'), findsOneWidget);
    expect(
      find.byKey(const Key('radar-precipitation-explanation')),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.text('Standard'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('radar-city-pin')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const Key('radar-city-pin')));
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('radar-time-ruler')),
      const Offset(-90, 0),
    );
    await tester.pump();
    expect(find.textContaining('prévision'), findsWidgets);
    expect(find.byKey(const Key('radar-now-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('radar-now-button')));
    await tester.pump();
    expect(find.textContaining('dernière observation'), findsOneWidget);

    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();
    expect(find.text('Lecture'), findsOneWidget);
    expect((radarBloc.state as RadarReady).isPlaying, isFalse);
    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Lecture'), findsOneWidget);
    expect((radarBloc.state as RadarReady).isPlaying, isFalse);
    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.byKey(const Key('radar-reset-button')));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();
    expect(find.text('Lecture'), findsOneWidget);

    await tester.tap(find.text('Prévisions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('forecast-pane')), findsOneWidget);
    expect(find.byKey(const Key('forecast-provenance-label')), findsOneWidget);
    expect(find.text('PRÉVISIONS HEURE PAR HEURE'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('forecast-pane')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRÉVISIONS SUR 10 JOURS'), findsOneWidget);
    expect(
      find.byKey(const Key('selected-navigation-indicator')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('open-settings-navigation')));
    await tester.pumpAndSettle();
    expect(find.text('Réglages'), findsWidgets);
    await tester.tap(find.byKey(const Key('main-location-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Paris').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Paris, France'), findsOneWidget);
  });

  testWidgets('restored selected place also becomes the radar center', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final locations = _MainLocationRepository(LocationCatalog.locations[2]);
    final radar = _RecordingRadarRepository();
    await tester.pumpWidget(
      ChetiwaApp(
        dependencies: ChetiwaDependencies.testing(
          forecastRepository: const FixtureForecastRepository(
            FixtureForecastDataSource(),
          ),
          radarRepository: radar,
          locationRepository: locations,
        ),
      ),
    );
    await _loadFixture(tester);

    expect(
      radar.requestedCoordinates,
      contains(LocationCatalog.locations[2].coordinates),
    );
    expect(radar.requestedCoordinates, hasLength(1));
  });

  testWidgets('a tapped rain push opens Radar on its target coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = ChetiwaDependencies.fixture();
    await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
    await _loadFixture(tester);
    dependencies.rainAlertNavigationController.open(
      const RainAlertNavigationIntent(
        eventId: 'event-sierra-leone',
        locationLabel: 'Freetown, Sierra Leone',
        coordinates: Coordinates(latitude: 8.4657, longitude: -13.2317),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      dependencies.activeLocationController.location?.coordinates,
      const Coordinates(latitude: 8.4657, longitude: -13.2317),
    );
  });
}

Future<void> _loadFixture(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

final class _RecordingRadarRepository implements RadarRepository {
  final requestedCoordinates = <Coordinates>[];
  final _delegate = const FixtureRadarRepository();

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) {
    requestedCoordinates.add(coordinates);
    return _delegate.getFrames(coordinates);
  }
}

final class _MainLocationRepository implements LocationRepository {
  _MainLocationRepository(this.mainLocation);

  ChetiwaLocation? mainLocation;

  @override
  Future<void> clearMainLocation() async => mainLocation = null;

  @override
  Future<ChetiwaLocation> getCurrentLocation() async =>
      LocationCatalog.locations.first;

  @override
  Future<ChetiwaLocation?> getMainLocation() async => mainLocation;

  @override
  Future<List<ChetiwaLocation>> getRecentLocations() async => const [];

  @override
  Future<bool> openLocationRecovery(LocationRecoveryAction action) async =>
      false;

  @override
  Future<void> remember(ChetiwaLocation location) async {}

  @override
  Future<void> removeRecentLocation(ChetiwaLocation location) async {}

  @override
  Future<ChetiwaLocation> resolveCoordinates(Coordinates coordinates) async =>
      LocationCatalog.forCoordinates(coordinates);

  @override
  Future<List<ChetiwaLocation>> search(String query) async => const [];

  @override
  Future<void> setMainLocation(ChetiwaLocation location) async =>
      mainLocation = location;
}
