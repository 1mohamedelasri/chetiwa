import 'package:chetiwa/app/theme/chetiwa_theme.dart';
import 'package:chetiwa/core/l10n/chetiwa_localizations.dart';
import 'package:chetiwa/core/weather/weather_data_health.dart';
import 'package:chetiwa/core/widgets/weather_data_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Unavailable weather data state remains visually stable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
          body: WeatherDataUnavailableView(
            issue: WeatherDataIssue.noRadarCoverage,
            domainLabel: 'RainViewer',
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Radar non couvert'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/weather_unavailable.png'),
    );
  });
}
