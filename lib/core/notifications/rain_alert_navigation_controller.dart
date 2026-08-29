import 'package:flutter/foundation.dart';

import '../location/coordinates.dart';

final class RainAlertNavigationIntent {
  const RainAlertNavigationIntent({
    required this.eventId,
    required this.locationLabel,
    required this.coordinates,
    this.section = 'radar',
  });

  static RainAlertNavigationIntent? fromData(Map<String, dynamic> data) {
    if (data['type'] != 'rain_alert') return null;
    final eventId = data['eventId']?.toString();
    final label = data['locationLabel']?.toString();
    final latitude = double.tryParse(data['latitude']?.toString() ?? '');
    final longitude = double.tryParse(data['longitude']?.toString() ?? '');
    if (eventId == null ||
        eventId.isEmpty ||
        label == null ||
        label.isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return RainAlertNavigationIntent(
      eventId: eventId,
      locationLabel: label,
      coordinates: Coordinates(latitude: latitude, longitude: longitude),
      section: data['section']?.toString() ?? 'radar',
    );
  }

  final String eventId;
  final String locationLabel;
  final Coordinates coordinates;
  final String section;
}

final class OfficialAlertNavigationIntent {
  const OfficialAlertNavigationIntent({
    required this.eventId,
    required this.departmentCode,
    required this.officialUrl,
  });

  static OfficialAlertNavigationIntent? fromData(Map<String, dynamic> data) {
    if (data['type'] != 'official_weather_alert' ||
        data['source'] != 'meteofrance') {
      return null;
    }
    final eventId = data['eventId']?.toString();
    final departmentCode = data['departmentCode']?.toString();
    final officialUrl = Uri.tryParse(data['officialUrl']?.toString() ?? '');
    if (eventId == null ||
        eventId.isEmpty ||
        departmentCode == null ||
        departmentCode.isEmpty ||
        officialUrl == null ||
        officialUrl.scheme != 'https' ||
        officialUrl.host != 'vigilance.meteofrance.fr') {
      return null;
    }
    return OfficialAlertNavigationIntent(
      eventId: eventId,
      departmentCode: departmentCode,
      officialUrl: officialUrl,
    );
  }

  final String eventId;
  final String departmentCode;
  final Uri officialUrl;
}

/// Retains a cold-start notification intent until WeatherScreen is mounted.
final class RainAlertNavigationController extends ChangeNotifier {
  RainAlertNavigationIntent? _pending;
  OfficialAlertNavigationIntent? _pendingOfficial;

  void open(RainAlertNavigationIntent intent) {
    _pending = intent;
    notifyListeners();
  }

  void openOfficial(OfficialAlertNavigationIntent intent) {
    _pendingOfficial = intent;
    notifyListeners();
  }

  RainAlertNavigationIntent? take() {
    final value = _pending;
    _pending = null;
    return value;
  }

  OfficialAlertNavigationIntent? takeOfficial() {
    final value = _pendingOfficial;
    _pendingOfficial = null;
    return value;
  }
}
