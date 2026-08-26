import 'package:chetiwa/app/app.dart';
import 'package:chetiwa/app/di/chetiwa_dependencies.dart';
import 'package:chetiwa/features/analytics/application/analytics_consent_controller.dart';
import 'package:chetiwa/features/monetization/application/app_feature_flag_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('asks once only when the statistics choice flag is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChetiwaApp(
        dependencies: ChetiwaDependencies.fixture(
          featureFlags: const AppFeatureFlags(
            premiumAvailable: false,
            adsEnabled: false,
            analyticsConsentPromptEnabled: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('analytics-consent-decline')), findsOneWidget);
    expect(find.byKey(const Key('analytics-consent-accept')), findsOneWidget);

    await tester.tap(find.byKey(const Key('analytics-consent-decline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('analytics-consent-decline')), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(AnalyticsConsentController.storageKey), isFalse);
  });

  testWidgets('does not ask before the rollout flag is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChetiwaApp(
        dependencies: ChetiwaDependencies.fixture(
          featureFlags: const AppFeatureFlags.disabled(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('analytics-consent-decline')), findsNothing);
  });
}
