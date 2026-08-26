import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/app/preferences/app_preferences_controller.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/fixture_location_repository.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/repositories/forecast_repository.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cycle de vie et reprise réseau', () {
    testWidgets('le retour au premier plan resynchronise météo et radar', (
      tester,
    ) async {
      final forecast = _CountingForecastRepository(
        const _StaticForecastRepository(),
      );
      final radar = _CountingRadarRepository(const FixtureRadarRepository());
      final dependencies = ChetiwaDependencies.testing(
        forecastRepository: forecast,
        radarRepository: radar,
        locationRepository: const FixtureLocationRepository(),
      );

      await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
      await _settleFixture(tester);
      expect(forecast.networkCalls, 1);
      expect(radar.networkCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settleFixture(tester);

      expect(forecast.networkCalls, 2);
      expect(radar.networkCalls, 2);
    });

    testWidgets(
      'inactive puis paused reprend automatiquement une animation active',
      (tester) async {
        final dependencies = ChetiwaDependencies.testing(
          forecastRepository: const _StaticForecastRepository(),
          radarRepository: const FixtureRadarRepository(),
          locationRepository: const FixtureLocationRepository(),
        );

        await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
        await _settleFixture(tester);
        await tester.tap(find.text('Radar'));
        await tester.pump();
        final radarBloc = tester
            .element(find.byKey(const ValueKey('radar'), skipOffstage: false))
            .read<RadarBloc>();
        await tester.pump(const Duration(milliseconds: 100));
        expect((radarBloc.state as RadarReady).isPlaying, isTrue);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect((radarBloc.state as RadarReady).isPlaying, isFalse);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 550));
        expect((radarBloc.state as RadarReady).isPlaying, isTrue);

        // A second quick lock/unlock is inside the 20 s network throttle but
        // must still resume playback.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect((radarBloc.state as RadarReady).isPlaying, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 550));
        expect((radarBloc.state as RadarReady).isPlaying, isTrue);
      },
    );
  });

  group('apparence, langue et écrans adaptatifs', () {
    testWidgets('le thème clair et l’anglais s’appliquent sans redémarrage', (
      tester,
    ) async {
      final preferences = AppPreferencesController(persist: false);
      await preferences.setThemeMode(ThemeMode.light);
      await preferences.setLanguage(ChetiwaLanguage.english);
      final dependencies = ChetiwaDependencies.testing(
        forecastRepository: const _StaticForecastRepository(),
        radarRepository: const FixtureRadarRepository(),
        locationRepository: const FixtureLocationRepository(),
        preferencesController: preferences,
      );

      await tester.pumpWidget(ChetiwaApp(dependencies: dependencies));
      await _settleFixture(tester);

      expect(find.text('Forecast'), findsOneWidget);
      expect(find.textContaining('No rain'), findsWidgets);
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.light);
      expect(materialApp.locale, const Locale('en'));
    });

    for (final profile in <({String name, Size size, double scale})>[
      (name: 'petit téléphone et texte 200 %', size: Size(320, 568), scale: 2),
      (name: 'téléphone standard', size: Size(390, 844), scale: 1),
      (name: 'orientation paysage compacte', size: Size(844, 390), scale: 1),
      (name: 'tablette', size: Size(800, 1280), scale: 1.3),
    ]) {
      testWidgets('${profile.name} ne produit aucun overflow', (tester) async {
        tester.view.physicalSize = profile.size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = profile.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          ChetiwaApp(
            dependencies: ChetiwaDependencies.testing(
              forecastRepository: const _StaticForecastRepository(),
              radarRepository: const FixtureRadarRepository(),
              locationRepository: const FixtureLocationRepository(),
            ),
          ),
        );
        await _settleFixture(tester);

        expect(tester.takeException(), isNull);
        if (find
            .byKey(const Key('compact-graph-scroll'))
            .evaluate()
            .isNotEmpty) {
          await tester.drag(
            find.byKey(const Key('compact-graph-scroll')),
            const Offset(0, -280),
          );
          await tester.pump();
        }
        expect(
          find.byKey(const Key('rain-chart'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('adaptive-ad-banner-slot')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('selected-navigation-indicator')),
          findsOneWidget,
        );
      });
    }
  });
}

Future<void> _settleFixture(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final class _CountingForecastRepository implements ForecastRepository {
  _CountingForecastRepository(this.delegate);

  final ForecastRepository delegate;
  int networkCalls = 0;

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) =>
      delegate.getCachedForecast(coordinates);

  @override
  Future<Forecast> getForecast(Coordinates coordinates) {
    networkCalls++;
    return delegate.getForecast(coordinates);
  }
}

final class _StaticForecastRepository implements ForecastRepository {
  const _StaticForecastRepository();

  @override
  Future<CachedForecast?> getCachedForecast(Coordinates coordinates) async =>
      null;

  @override
  Future<Forecast> getForecast(Coordinates coordinates) async {
    final now = DateTime.now().toUtc();
    return Forecast(
      locationName: 'Paris, France',
      updatedAt: now,
      temperatureCelsius: 22,
      windKph: 12,
      timeZone: 'Europe/Paris',
      brief: const WeatherBrief(
        type: WeatherBriefType.dry,
        intensity: RainIntensity.none,
        headline: 'Pas de pluie dans les 2 h',
        detail: 'Conditions sèches pour sortir',
      ),
      points: List.generate(
        9,
        (index) => RainPoint(
          time: now.add(Duration(minutes: index * 15)),
          rateMmPerHour: 0,
          intensity: RainIntensity.none,
        ),
      ),
      windows: const [],
    );
  }
}

final class _CountingRadarRepository implements RadarRepository {
  _CountingRadarRepository(this.delegate);

  final RadarRepository delegate;
  int networkCalls = 0;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) =>
      delegate.getCachedFrames(coordinates);

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) {
    networkCalls++;
    return delegate.getFrames(coordinates);
  }
}
