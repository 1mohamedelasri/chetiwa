import 'package:chetiwa/core/l10n/chetiwa_localizations.dart';
import 'package:chetiwa/features/legal/presentation/sources_licenses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows source attributions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: ChetiwaLocalizations.supportedLocales,
        localizationsDelegates: const [
          ChetiwaLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const SourcesLicensesScreen(),
      ),
    );

    expect(find.text('Sources et licences'), findsOneWidget);
    expect(find.text('Open-Meteo'), findsOneWidget);
    expect(find.text('LibreWXR'), findsOneWidget);
  });

  testWidgets('localizes source purposes in English', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: ChetiwaLocalizations.supportedLocales,
        localizationsDelegates: const [
          ChetiwaLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const SourcesLicensesScreen(),
      ),
    );

    expect(find.text('Sources and licences'), findsOneWidget);
    expect(find.text('Forecasts and place search'), findsOneWidget);
    expect(
      find.text('Precipitation radar imagery via LibreWXR'),
      findsOneWidget,
    );
    expect(
      find.text('Hybrid satellite basemap and location picker map'),
      findsOneWidget,
    );
    expect(find.text('Google Maps Platform'), findsOneWidget);
  });
}
