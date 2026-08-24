import 'dart:convert';
import 'dart:math';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/network/chetiwa_api_client.dart';
import 'package:chetiwa/features/monetization/application/saved_places_controller.dart';
import 'package:chetiwa/features/monetization/application/usage_quota_controller.dart';
import 'package:chetiwa/features/monetization/data/chetiwa_radar_session_gateway.dart';
import 'package:chetiwa/features/monetization/domain/premium_entitlement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  test('backend session opening sends plan and synchronizes usage', () async {
    late http.Request captured;
    var requestCount = 0;
    final api = ChetiwaApiClient(
      baseUri: Uri.parse('https://api.chetiwa.test'),
      client: MockClient((request) async {
        requestCount++;
        captured = request;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'session': <String, Object?>{
                'allowed': true,
                'enforced': false,
                'used': 7,
                'limit': 200,
                'remaining': 193,
                'resetAt': '2026-09-01T00:00:00.000Z',
              },
            },
          }),
          201,
        );
      }),
    );
    final entitlement = EntitlementController(
      gateway: FixturePremiumPurchaseGateway(),
      persist: false,
      autoSync: false,
    );
    await entitlement.setFixturePremium(true);
    final quota = UsageQuotaController(
      entitlement: entitlement,
      persist: false,
      radarSessionGateway: ChetiwaRadarSessionGateway(api, random: Random(7)),
    );

    final decisions = await Future.wait(<Future<bool>>[
      quota.openRadarSession(),
      quota.openRadarSession(),
    ]);

    expect(decisions, everyElement(isTrue));
    expect(requestCount, 1);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/radar/sessions');
    expect(captured.headers['x-chetiwa-plan'], 'premium');
    expect(
      captured.headers['x-chetiwa-radar-session-id'],
      matches(RegExp(r'^[a-f0-9]{32}$')),
    );
    expect(
      captured.headers['x-chetiwa-device-id'],
      matches(RegExp(r'^[a-f0-9]{32}$')),
    );
    expect(quota.radarSessions.used, 7);
    expect(quota.radarSessions.limit, 200);

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
