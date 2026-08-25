import 'package:chetiwa/app/theme/chetiwa_theme.dart';
import 'package:chetiwa/core/l10n/chetiwa_localizations.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/radar/application/radar_bloc.dart';
import 'package:chetiwa/features/radar/data/repositories/fixture_radar_repository.dart';
import 'package:chetiwa/features/radar/presentation/widgets/radar_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('free Radar exposes only the OpenFreeMap standard basemap', (
    tester,
  ) async {
    await _pumpRadar(tester, satelliteAvailable: false);

    await tester.tap(find.byKey(const Key('radar-layers-button')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Satellite'), findsNothing);
    Navigator.of(tester.element(find.text('Standard'))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _pumpRadar(
  WidgetTester tester, {
  required bool satelliteAvailable,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));
  final forecast = await FixtureForecastDataSource(clock: clock).load();
  final snapshot = ForecastSnapshotBuilder.build(
    forecast: forecast,
    nowUtc: clock.nowUtc,
  );
  final radarBloc = RadarBloc(
    FixtureRadarRepository(clock: clock),
    clock: clock,
  )..add(const RadarRequested());
  addTearDown(radarBloc.close);

  await tester.pumpWidget(
    MaterialApp(
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
          child: RadarPane(
            forecast: forecast,
            snapshot: snapshot,
            satelliteAvailable: satelliteAvailable,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
