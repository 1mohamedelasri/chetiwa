import 'package:chetiwa/core/l10n/chetiwa_localizations.dart';
import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/core/weather/weather_data_provenance.dart';
import 'package:chetiwa/features/analytics/application/analytics_consent_controller.dart';
import 'package:chetiwa/features/analytics/application/analytics_tracker.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
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
  final clock = FixedWeatherClock(DateTime.utc(2026, 9, 30, 18, 55));
  late Forecast forecast;
  setUpAll(() async {
    forecast = await FixtureForecastDataSource(clock: clock).load();
  });

  for (final source in <String?>['radar', 'nwp', null]) {
    testWidgets('extended frame labels ${source ?? 'missing point'} honestly', (
      tester,
    ) async {
      final bloc = RadarBloc(
        _PointFrames([
          RadarFrame(time: clock.nowUtc, progress: 0),
          RadarFrame(
            time: clock.nowUtc.add(const Duration(minutes: 90)),
            progress: 1,
            kind: WeatherDataKind.modelForecast,
            pointRainRateMmPerHour: source == null ? null : 0.5,
            pointRainSource: source,
          ),
        ]),
        clock: clock,
        allowModelForecast: true,
      )..add(const RadarRequested());
      addTearDown(bloc.close);
      final tracker = AnalyticsTracker(
        consent: AnalyticsConsentController(
          initiallyEnabled: false,
          updateCollection: (_) async {},
        ),
        logEvent: (_, {parameters}) async {},
      );
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: tracker,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: ChetiwaLocalizations.supportedLocales,
            localizationsDelegates: const [
              ChetiwaLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: BlocProvider.value(
                value: bloc,
                child: RadarPane(
                  forecast: forecast,
                  snapshot: ForecastSnapshotBuilder.build(
                    forecast: forecast,
                    nowUtc: clock.nowUtc,
                  ),
                  isActive: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      bloc.add(const RadarFrameSelected(1));
      await tester.pump();
      await tester.pump();
      if (source == 'radar') {
        expect(
          find.textContaining('radar projection 0.5 mm/h'),
          findsOneWidget,
        );
        expect(find.textContaining('weather model'), findsNothing);
      } else if (source != null) {
        expect(
          find.textContaining('provider forecast 0.5 mm/h'),
          findsOneWidget,
        );
        expect(find.textContaining('radar projection'), findsNothing);
      } else {
        expect(find.textContaining('weather model'), findsOneWidget);
        expect(find.textContaining('radar projection'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

final class _PointFrames implements RadarRepository {
  const _PointFrames(this.frames);
  final List<RadarFrame> frames;
  @override
  Future<CachedRadarFrames?> getCachedFrames(Coordinates coordinates) async =>
      null;
  @override
  Future<List<RadarFrame>> getFrames(Coordinates coordinates) async => frames;
}
