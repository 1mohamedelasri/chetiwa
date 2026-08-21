import 'package:chetiwa/app/theme/chetiwa_theme.dart';
import 'package:chetiwa/core/l10n/chetiwa_localizations.dart';
import 'package:chetiwa/core/time/weather_clock.dart';
import 'package:chetiwa/features/forecast/application/graph_horizon_cubit.dart';
import 'package:chetiwa/features/forecast/data/datasources/fixture_forecast_data_source.dart';
import 'package:chetiwa/features/forecast/domain/entities/forecast.dart';
import 'package:chetiwa/features/forecast/domain/services/forecast_snapshot_builder.dart';
import 'package:chetiwa/features/forecast/presentation/widgets/graph_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  testWidgets('Graph remains visually stable in both themes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final clock = FixedWeatherClock(DateTime.utc(2026, 8, 20, 12));
    final forecast = await FixtureForecastDataSource(clock: clock).load();
    final longNameForecast = await FixtureForecastDataSource(
      clock: clock,
      locationName: 'Saint-Rémy-lès-Chevreuse, Île-de-France, France',
    ).load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ChetiwaTheme.light,
        locale: const Locale('fr'),
        supportedLocales: ChetiwaLocalizations.supportedLocales,
        localizationsDelegates: const [
          ChetiwaLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: _GraphGoldenPanel(
                  title: 'Paris, France',
                  forecast: forecast,
                  clock: clock,
                  theme: ChetiwaTheme.dark,
                ),
              ),
              Expanded(
                child: _GraphGoldenPanel(
                  title: longNameForecast.locationName,
                  forecast: longNameForecast,
                  clock: clock,
                  theme: ChetiwaTheme.light,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byKey(const Key('rain-chart')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/weather_graph_themes.png'),
    );
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final class _GraphGoldenPanel extends StatelessWidget {
  const _GraphGoldenPanel({
    required this.title,
    required this.forecast,
    required this.clock,
    required this.theme,
  });

  final String title;
  final Forecast forecast;
  final WeatherClock clock;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final snapshot = ForecastSnapshotBuilder.build(
      forecast: forecast,
      nowUtc: clock.nowUtc,
    );
    return Theme(
      data: theme,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: BlocProvider(
                create: (_) => GraphHorizonCubit(),
                child: GraphPane(forecast: forecast, snapshot: snapshot),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
