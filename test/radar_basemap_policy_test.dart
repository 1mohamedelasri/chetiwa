import 'package:chetiwa/features/radar/domain/services/radar_basemap_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('satellite requires Premium, its remote switch and an Esri key', () {
    expect(
      RadarBasemapPolicy.canUsePremiumSatellite(
        isPremium: true,
        premiumSatelliteEnabled: true,
        arcGisConfigured: true,
      ),
      isTrue,
    );

    for (final missingGate in <({bool premium, bool flag, bool key})>[
      (premium: false, flag: true, key: true),
      (premium: true, flag: false, key: true),
      (premium: true, flag: true, key: false),
    ]) {
      expect(
        RadarBasemapPolicy.canUsePremiumSatellite(
          isPremium: missingGate.premium,
          premiumSatelliteEnabled: missingGate.flag,
          arcGisConfigured: missingGate.key,
        ),
        isFalse,
      );
    }
  });
}
