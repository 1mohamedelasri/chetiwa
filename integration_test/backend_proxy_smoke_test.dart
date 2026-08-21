import 'package:chetiwa/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  testWidgets('loads Graph, Radar and Forecast through the Chetiwa backend', (
    tester,
  ) async {
    await tester.pumpWidget(const ChetiwaApp());
    await _waitFor(tester, find.byKey(const Key('rain-chart')));
    expect(find.text('Paris, France'), findsOneWidget);

    await tester.tap(find.text('Radar'));
    await tester.pump();
    await _waitFor(tester, find.byKey(const Key('radar-local-time')));

    await tester.tap(find.text('Prévisions'));
    await tester.pump();
    await _waitFor(tester, find.byKey(const Key('forecast-pane')));
    expect(find.text('PRÉVISIONS HEURE PAR HEURE'), findsOneWidget);
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsOneWidget);
}
