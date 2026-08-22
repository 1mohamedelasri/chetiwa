import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens on Graph and switches to Radar without changing route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChetiwaApp(dependencies: ChetiwaDependencies.fixture()),
    );
    await _loadFixture(tester);

    expect(
      (tester.getCenter(find.text('Chetiwa')).dy -
              tester.getCenter(find.text('Paris, France')).dy)
          .abs(),
      lessThan(4),
    );
    expect(find.byKey(const Key('open-settings-navigation')), findsOneWidget);
    expect(find.byKey(const Key('rain-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('rain-chart-cursor-now')), findsOneWidget);
    expect(find.byKey(const Key('graph-provenance-label')), findsOneWidget);
    expect(find.text('2H'), findsOneWidget);
    expect(find.text('Graph'), findsOneWidget);
    expect(find.byKey(const Key('adaptive-ad-banner-slot')), findsOneWidget);
    expect(
      find.byKey(const Key('selected-navigation-indicator')),
      findsOneWidget,
    );

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

    expect(find.text('Lecture'), findsOneWidget);
    expect(find.byKey(const Key('radar-city-pin')), findsOneWidget);
    expect(find.byKey(const Key('radar-time-ruler')), findsOneWidget);
    expect(find.byKey(const Key('radar-reset-button')), findsOneWidget);
    expect(find.text('Paris, France'), findsOneWidget);
    expect(find.textContaining('dernière observation'), findsOneWidget);

    await tester.tap(find.byKey(const Key('radar-layers-button')));
    await tester.pumpAndSettle();
    expect(find.text('Couches de la carte'), findsOneWidget);
    expect(find.text('Satellite'), findsOneWidget);
    expect(find.text('Sombre'), findsOneWidget);
    expect(find.text('Clair'), findsOneWidget);
    expect(find.text('Routes'), findsOneWidget);
    expect(find.text('Radar de précipitations'), findsOneWidget);
    expect(find.text('Réduction du bruit'), findsOneWidget);
    expect(find.text('Échos faibles'), findsOneWidget);
    expect(
      find.byKey(const Key('readable-radar-palette-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('weak-radar-echoes-toggle')), findsOneWidget);
    await tester.tap(find.text('Clair'));
    await tester.pump();
    await tester.tapAt(const Offset(8, 8));
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
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();
    expect(find.text('Lecture'), findsOneWidget);

    await tester.tap(find.byKey(const Key('radar-reset-button')));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.byKey(const Key('radar-playback-button')));
    await tester.pump();

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
  });
}

Future<void> _loadFixture(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}
