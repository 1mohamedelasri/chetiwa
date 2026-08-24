import 'package:chetiwa/features/monetization/application/app_feature_flag_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fails closed before the first valid server response', () {
    final controller = AppFeatureFlagController(persist: false);
    addTearDown(controller.dispose);

    expect(controller.premiumAvailable, isFalse);
    expect(controller.adsEnabled, isFalse);
  });

  test('loads public rollout flags without granting an entitlement', () async {
    final controller = AppFeatureFlagController(
      gateway: const _FixedGateway(
        AppFeatureFlags(premiumAvailable: true, adsEnabled: true),
      ),
      persist: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.premiumAvailable, isTrue);
    expect(controller.adsEnabled, isTrue);
  });

  test('keeps the last valid flags when refresh fails', () async {
    final controller = AppFeatureFlagController(
      gateway: _SequenceGateway(),
      persist: false,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.refresh();

    expect(controller.premiumAvailable, isTrue);
    expect(controller.adsEnabled, isFalse);
  });
}

final class _FixedGateway implements AppFeatureFlagGateway {
  const _FixedGateway(this.value);

  final AppFeatureFlags value;

  @override
  Future<AppFeatureFlags> load() async => value;
}

final class _SequenceGateway implements AppFeatureFlagGateway {
  var calls = 0;

  @override
  Future<AppFeatureFlags> load() async {
    calls++;
    if (calls > 1) throw StateError('offline');
    return const AppFeatureFlags(premiumAvailable: true, adsEnabled: false);
  }
}
