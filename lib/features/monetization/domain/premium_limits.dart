import 'premium_entitlement.dart';

final class PremiumLimits {
  const PremiumLimits({
    required this.maxSavedPlaces,
    required this.maxRadarFrames,
    required this.radarHistoryHours,
    required this.monthlyRadarSessions,
  });

  const PremiumLimits.free()
    : this(
        // The device location is the single Free place. Named saved places
        // are a Chetiwa+ feature.
        maxSavedPlaces: 0,
        maxRadarFrames: 12,
        radarHistoryHours: 2,
        monthlyRadarSessions: 20,
      );

  const PremiumLimits.premium()
    : this(
        maxSavedPlaces: 12,
        maxRadarFrames: 24,
        radarHistoryHours: 6,
        monthlyRadarSessions: 200,
      );

  final int maxSavedPlaces;
  final int maxRadarFrames;
  final int radarHistoryHours;
  final int monthlyRadarSessions;

  static PremiumLimits forEntitlement(EntitlementController entitlement) =>
      entitlement.isPremium
      ? const PremiumLimits.premium()
      : const PremiumLimits.free();
}
