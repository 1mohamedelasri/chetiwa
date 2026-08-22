import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/features/monetization/application/saved_places_controller.dart';
import 'package:chetiwa/features/monetization/application/usage_quota_controller.dart';
import 'package:chetiwa/features/monetization/domain/premium_entitlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final paris = const ChetiwaLocation(
    city: 'Paris',
    country: 'France',
    coordinates: Coordinates.paris,
  );

  test(
    'Free blocks named places and Premium unlocks multiple places',
    () async {
      final entitlement = EntitlementController(
        gateway: FixturePremiumPurchaseGateway(),
        persist: false,
        autoSync: false,
      );
      final places = SavedPlacesController(
        entitlement: entitlement,
        persist: false,
      );

      expect(await places.add(name: 'Maison', location: paris), isFalse);
      await entitlement.setFixturePremium(true);
      expect(await places.add(name: 'Maison', location: paris), isTrue);
      expect(await places.add(name: 'Travail', location: paris), isTrue);
      expect(places.places.map((place) => place.name), ['Maison', 'Travail']);

      places.dispose();
      entitlement.dispose();
    },
  );

  test('quota exposes usage and blocks sessions at the Free limit', () async {
    final entitlement = EntitlementController(
      gateway: FixturePremiumPurchaseGateway(),
      persist: false,
      autoSync: false,
    );
    final quota = UsageQuotaController(
      entitlement: entitlement,
      persist: false,
    );

    for (var index = 0; index < 20; index++) {
      expect(await quota.consumeRadarSession(), isTrue);
    }
    expect(await quota.consumeRadarSession(), isFalse);
    expect(quota.radarSessions.used, 20);
    expect(quota.radarSessions.remaining, 0);

    quota.dispose();
    entitlement.dispose();
  });

  test(
    'fixture purchase activates Premium and exposes store products',
    () async {
      final entitlement = EntitlementController(
        gateway: FixturePremiumPurchaseGateway(),
        persist: false,
        autoSync: false,
      );

      await entitlement.loadProducts();
      expect(entitlement.products, hasLength(2));
      await entitlement.purchase(EntitlementController.yearlyProductId);
      expect(entitlement.isPremium, isTrue);

      entitlement.dispose();
    },
  );
}
