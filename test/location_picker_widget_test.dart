import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'location picker searches worldwide and exposes current position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChetiwaApp(dependencies: ChetiwaDependencies.fixture()),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      await tester.tap(find.text('Paris, France'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location-search-field')), findsOneWidget);
      expect(find.byKey(const Key('current-location-tile')), findsOneWidget);
      expect(find.text('VILLES POPULAIRES'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('location-search-field')),
        'Tokyo',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('RÉSULTATS'), findsOneWidget);
      final tokyoResult = find.widgetWithText(ListTile, 'Tokyo');
      expect(tokyoResult, findsOneWidget);
      await tester.scrollUntilVisible(
        tokyoResult,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(tokyoResult);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Tokyo, Japon'), findsOneWidget);
    },
  );
}
