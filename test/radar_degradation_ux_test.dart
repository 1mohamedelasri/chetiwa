import 'package:chetiwa/app/theme/chetiwa_theme.dart';
import 'package:chetiwa/core/l10n/chetiwa_localizations.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_health.dart';
import 'package:chetiwa/core/widgets/weather_data_status.dart';
import 'package:chetiwa/features/analytics/application/analytics_consent_controller.dart';
import 'package:chetiwa/features/analytics/application/analytics_tracker.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/domain/entities/radar_frame.dart';
import 'package:chetiwa/features/radar/domain/repositories/radar_repository.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'cached radar hides provider failures and reports an anonymous event',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));
      final forecast = await FixtureForecastDataSource(clock: clock).load();
      final snapshot = ForecastSnapshotBuilder.build(
        forecast: forecast,
        nowUtc: clock.nowUtc,
      );
      final events = <({String name, Map<String, Object>? parameters})>[];
      final tracker = AnalyticsTracker(
        consent: AnalyticsConsentController(
          initiallyEnabled: true,
          updateCollection: (_) async {},
        ),
        logEvent: (name, {parameters}) async {
          events.add((name: name, parameters: parameters));
        },
      );
      final radarBloc = RadarBloc(
        _StaleCacheRadarRepository(clock.nowUtc),
        clock: clock,
      )..add(const RadarRequested());
      addTearDown(radarBloc.close);

      await tester.pumpWidget(
        RepositoryProvider.value(
          value: tracker,
          child: MaterialApp(
            theme: ChetiwaTheme.dark,
            locale: const Locale('fr'),
            supportedLocales: ChetiwaLocalizations.supportedLocales,
            localizationsDelegates: const [
              ChetiwaLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: BlocProvider.value(
                value: radarBloc,
                child: RadarPane(forecast: forecast, snapshot: snapshot),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(WeatherDataStatusBanner), findsNothing);
      expect(find.byKey(const Key('weather-data-retry')), findsNothing);
      expect(find.byKey(const Key('fallback-radar-none')), findsOneWidget);
      expect(events, hasLength(1));
      expect(events.single.name, 'radar_availability_issue');
      expect(events.single.parameters, <String, Object>{
        'issue': 'providerUnavailable',
        'surface': 'metadata',
        'cached_data_visible': 'true',
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _StaleCacheRadarRepository implements RadarRepository {
  const _StaleCacheRadarRepository(this.nowUtc);

  final DateTime nowUtc;

  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      CachedRadarFrames(
        cachedAt: nowUtc.subtract(const Duration(minutes: 32)),
        frames: List.generate(
          4,
          (index) => RadarFrame(
            time: nowUtc.subtract(Duration(minutes: (3 - index) * 10)),
            progress: index / 3,
          ),
          growable: false,
        ),
      );

  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) =>
      Future<List<RadarFrame>>.error(
        const WeatherDataException(
          WeatherDataIssue.providerUnavailable,
          'simulated outage',
        ),
      );
}
