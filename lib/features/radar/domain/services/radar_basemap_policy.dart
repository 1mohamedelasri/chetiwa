abstract final class RadarBasemapPolicy {
  static bool canUsePremiumSatellite({
    required bool isPremium,
    required bool premiumSatelliteEnabled,
    required bool arcGisConfigured,
  }) => isPremium && premiumSatelliteEnabled && arcGisConfigured;
}
