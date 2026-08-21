import 'package:chetiwa/features/analytics/application/analytics_consent_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('enables analytics only after the SDK accepts the choice', () async {
    final calls = <bool>[];
    final controller = AnalyticsConsentController(
      initiallyEnabled: false,
      updateCollection: (enabled) async => calls.add(enabled),
    );

    final changed = await controller.setEnabled(true);

    expect(changed, isTrue);
    expect(controller.isEnabled, isTrue);
    expect(calls, [true]);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(AnalyticsConsentController.storageKey), isTrue);
  });

  test('keeps collection disabled when the SDK refuses activation', () async {
    final controller = AnalyticsConsentController(
      initiallyEnabled: false,
      updateCollection: (_) => Future<void>.error(StateError('unavailable')),
    );

    final changed = await controller.setEnabled(true);

    expect(changed, isFalse);
    expect(controller.isEnabled, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(AnalyticsConsentController.storageKey),
      isFalse,
    );
  });

  test(
    'clearing local data revokes analytics and removes the stored choice',
    () async {
      SharedPreferences.setMockInitialValues({
        AnalyticsConsentController.storageKey: true,
      });
      final calls = <bool>[];
      final controller = AnalyticsConsentController(
        initiallyEnabled: true,
        updateCollection: (enabled) async => calls.add(enabled),
      );

      await controller.clear();

      expect(controller.isEnabled, isFalse);
      expect(calls, [false]);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(AnalyticsConsentController.storageKey),
        isFalse,
      );
    },
  );
}
