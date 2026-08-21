import 'dart:convert';

import 'package:chetiwa/core/location/coordinates.dart';
import 'package:chetiwa/core/location/device_location_provider.dart';
import 'package:chetiwa/core/location/location_repository.dart';
import 'package:chetiwa/core/location/open_meteo_location_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('search maps worldwide localized geocoding results', () async {
    final repository = OpenMeteoLocationRepository(
      client: MockClient((request) async {
        expect(request.url.host, 'geocoding-api.open-meteo.com');
        expect(request.url.queryParameters['name'], 'Tokyo');
        expect(request.url.queryParameters['language'], 'fr');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Tokyo',
                'country': 'Japon',
                'admin1': 'Préfecture de Tokyo',
                'latitude': 35.6895,
                'longitude': 139.69171,
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
      deviceLocationProvider: const _FakeDeviceLocationProvider(),
    );

    final results = await repository.search('Tokyo');

    expect(results, hasLength(1));
    expect(results.single.label, 'Tokyo, Japon');
    expect(results.single.details, 'Préfecture de Tokyo · Japon');
    expect(results.single.coordinates.latitude, 35.6895);
  });

  test(
    'current location uses device coordinates without a network lookup',
    () async {
      final repository = OpenMeteoLocationRepository(
        client: MockClient((_) async => throw StateError('unexpected request')),
        deviceLocationProvider: const _FakeDeviceLocationProvider(),
      );

      final location = await repository.getCurrentLocation();

      expect(location.label, 'Ma position actuelle');
      expect(
        location.coordinates,
        const Coordinates(latitude: 1, longitude: 2),
      );
      expect(location.acquisition, LocationAcquisition.precise);
    },
  );
}

final class _FakeDeviceLocationProvider implements DeviceLocationProvider {
  const _FakeDeviceLocationProvider();

  @override
  Future<DeviceLocationFix> getCurrentLocationFix() async =>
      const DeviceLocationFix(
        coordinates: Coordinates(latitude: 1, longitude: 2),
        acquisition: LocationAcquisition.precise,
      );

  @override
  Future<bool> openRecovery(LocationRecoveryAction action) async => false;
}
