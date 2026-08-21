import 'package:chetiwa/app/theme/chetiwa_theme.dart';
import 'package:chetiwa/core/notifications/notification_permission_gateway.dart';
import 'package:chetiwa/core/location/active_location_controller.dart';
import 'package:chetiwa/core/location/fixture_location_repository.dart';
import 'package:chetiwa/features/alerts/application/alert_preferences_controller.dart';
import 'package:chetiwa/features/alerts/data/chetiwa_alert_api.dart';
import 'package:chetiwa/features/alerts/presentation/alerts_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('explains notification use before requesting permission', (
    tester,
  ) async {
    final preferences = AlertPreferencesController(persist: false);
    final gateway = FixtureNotificationPermissionGateway();
    final activeLocation = ActiveLocationController(
      const FixtureLocationRepository(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AlertPreferencesController>.value(
            value: preferences,
          ),
          Provider<NotificationPermissionGateway>.value(value: gateway),
          ChangeNotifierProvider<ActiveLocationController>.value(
            value: activeLocation,
          ),
        ],
        child: MaterialApp(
          theme: ChetiwaTheme.light,
          home: const AlertsSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(preferences.enabled, isFalse);
    await tester.tap(find.byKey(const Key('smart-alerts-enabled-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Autoriser les alertes pluie ?'), findsOneWidget);
    expect(preferences.enabled, isFalse);

    await tester.tap(
      find.byKey(const Key('request-notification-permission-button')),
    );
    await tester.pumpAndSettle();

    expect(preferences.enabled, isTrue);
    expect(find.text('Autorisées sur cet appareil'), findsOneWidget);
  });

  testWidgets('stores configurable thresholds only after alerts are enabled', (
    tester,
  ) async {
    final preferences = AlertPreferencesController(persist: false);
    final activeLocation = ActiveLocationController(
      const FixtureLocationRepository(),
    );
    await preferences.setEnabled(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AlertPreferencesController>.value(
            value: preferences,
          ),
          Provider<NotificationPermissionGateway>.value(
            value: FixtureNotificationPermissionGateway(
              initial: NotificationAuthorization.authorized,
            ),
          ),
          ChangeNotifierProvider<ActiveLocationController>.value(
            value: activeLocation,
          ),
        ],
        child: MaterialApp(
          theme: ChetiwaTheme.light,
          home: const AlertsSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Forte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forte'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('quiet-hours-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiet-hours-switch')));
    await tester.pump();

    expect(preferences.minimumIntensity, RainAlertIntensity.heavy);
    expect(preferences.quietHoursEnabled, isTrue);
  });
}
