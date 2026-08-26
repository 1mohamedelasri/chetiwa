import 'package:chetiwa/core/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Premium radar test mode can never be enabled in production', () {
    if (ApiConfig.isProduction) {
      expect(ApiConfig.premiumRadarTestMode, isFalse);
      return;
    }

    expect(
      ApiConfig.premiumRadarTestMode,
      const bool.fromEnvironment(
        'CHETIWA_PREMIUM_RADAR_TEST_MODE',
        defaultValue: false,
      ),
    );
  });
}
