import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'coordinates.dart';
import 'location_repository.dart';

abstract interface class DeviceLocationProvider {
  Future<DeviceLocationFix> getCurrentLocationFix();

  Future<bool> openRecovery(LocationRecoveryAction action);
}

final class DeviceLocationFix {
  const DeviceLocationFix({
    required this.coordinates,
    required this.acquisition,
  });

  final Coordinates coordinates;
  final LocationAcquisition acquisition;
}

final class GeolocatorDeviceLocationProvider implements DeviceLocationProvider {
  const GeolocatorDeviceLocationProvider();

  @override
  Future<DeviceLocationFix> getCurrentLocationFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'La localisation est désactivée sur cet appareil.',
        issue: LocationIssue.serviceDisabled,
        recoveryAction: LocationRecoveryAction.locationSettings,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        'Autorisation refusée. Autorisez Chetiwa dans les réglages.',
        issue: LocationIssue.permissionDenied,
        recoveryAction: LocationRecoveryAction.appSettings,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Localisation bloquée. Autorisez Chetiwa dans les réglages.',
        issue: LocationIssue.permissionBlocked,
        recoveryAction: LocationRecoveryAction.appSettings,
      );
    }

    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return DeviceLocationFix(
        coordinates: Coordinates(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
        acquisition: accuracy == LocationAccuracyStatus.reduced
            ? LocationAcquisition.reducedAccuracy
            : LocationAcquisition.precise,
      );
    } on Object catch (error) {
      Position? lastPosition;
      try {
        lastPosition = await Geolocator.getLastKnownPosition();
      } on Object {
        // The current-position error below remains the useful recovery path.
      }
      if (lastPosition == null) {
        throw LocationException(
          error is TimeoutException
              ? 'Le GPS met trop de temps à répondre. Réessayez dans un endroit dégagé.'
              : 'Position indisponible. Activez le GPS puis réessayez.',
          issue: LocationIssue.unavailable,
          recoveryAction: LocationRecoveryAction.locationSettings,
        );
      }
      return DeviceLocationFix(
        coordinates: Coordinates(
          latitude: lastPosition.latitude,
          longitude: lastPosition.longitude,
        ),
        acquisition: LocationAcquisition.lastKnownPosition,
      );
    }
  }

  @override
  Future<bool> openRecovery(LocationRecoveryAction action) => switch (action) {
    LocationRecoveryAction.locationSettings =>
      Geolocator.openLocationSettings(),
    LocationRecoveryAction.appSettings => Geolocator.openAppSettings(),
  };
}
