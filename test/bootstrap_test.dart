import 'dart:async';

import 'package:chetiwa/app/bootstrap/chetiwa_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a branded frame before platform services finish', (
    tester,
  ) async {
    final initialization = Completer<ChetiwaBootstrapData>();

    await tester.pumpWidget(
      ChetiwaBootstrap(
        loader: () => initialization.future,
        appBuilder: (data) => MaterialApp(
          home: Text(
            data.firebaseAvailable ? 'firebase-ready' : 'degraded-ready',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('chetiwa-bootstrap-preparation')),
      findsOneWidget,
    );
    expect(find.text('Chetiwa'), findsOneWidget);
    expect(find.textContaining('Préparation'), findsOneWidget);

    initialization.complete(
      const ChetiwaBootstrapData(
        firebaseAvailable: false,
        analyticsConsent: false,
        analyticsConsentDecided: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('degraded-ready'), findsOneWidget);
    expect(
      find.byKey(const Key('chetiwa-bootstrap-preparation')),
      findsNothing,
    );
  });
}
