import '../../../core/network/chetiwa_api_client.dart';

enum RainAlertIntensity {
  light,
  moderate,
  heavy;

  static RainAlertIntensity parse(String value) => values.firstWhere(
    (candidate) => candidate.name == value,
    orElse: () => throw const FormatException('Unknown alert intensity'),
  );
}

final class AlertLocationInput {
  const AlertLocationInput({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.timeZone,
  });

  final String label;
  final double latitude;
  final double longitude;
  final String timeZone;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'latitude': latitude,
    'longitude': longitude,
    'timeZone': timeZone,
  };
}

final class AlertQuietHoursInput {
  const AlertQuietHoursInput({
    required this.enabled,
    required this.start,
    required this.end,
  });

  final bool enabled;
  final String start;
  final String end;

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'start': start,
    'end': end,
  };
}

final class RainAlertInput {
  const RainAlertInput({
    required this.location,
    required this.leadMinutes,
    required this.minimumIntensity,
    required this.quietHours,
    required this.enabled,
  });

  final AlertLocationInput location;
  final int leadMinutes;
  final RainAlertIntensity minimumIntensity;
  final AlertQuietHoursInput quietHours;
  final bool enabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'location': location.toJson(),
    'leadMinutes': leadMinutes,
    'minimumIntensity': minimumIntensity.name,
    'quietHours': quietHours.toJson(),
    'enabled': enabled,
  };
}

final class RainAlertRule {
  const RainAlertRule({
    required this.id,
    required this.location,
    required this.leadMinutes,
    required this.minimumIntensity,
    required this.quietHours,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RainAlertRule.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>;
    final quietHours = json['quietHours'] as Map<String, dynamic>;
    return RainAlertRule(
      id: json['id'] as String,
      location: AlertLocationInput(
        label: location['label'] as String,
        latitude: (location['latitude'] as num).toDouble(),
        longitude: (location['longitude'] as num).toDouble(),
        timeZone: location['timeZone'] as String,
      ),
      leadMinutes: json['leadMinutes'] as int,
      minimumIntensity: RainAlertIntensity.parse(
        json['minimumIntensity'] as String,
      ),
      quietHours: AlertQuietHoursInput(
        enabled: quietHours['enabled'] as bool,
        start: quietHours['start'] as String,
        end: quietHours['end'] as String,
      ),
      enabled: json['enabled'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final AlertLocationInput location;
  final int leadMinutes;
  final RainAlertIntensity minimumIntensity;
  final AlertQuietHoursInput quietHours;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class ChetiwaAlertApi {
  const ChetiwaAlertApi(this._api);

  final ChetiwaApiClient _api;

  Future<void> registerDevice({
    required String platform,
    required String locale,
    required String timeZone,
    required bool notificationsEnabled,
    String? pushToken,
  }) async {
    await _api.postData('/v1/devices', <String, Object?>{
      'platform': platform,
      'locale': locale,
      'timeZone': timeZone,
      'notificationsEnabled': notificationsEnabled,
      if (pushToken != null) 'pushToken': pushToken,
    });
  }

  Future<void> deleteDevice() => _api.delete('/v1/devices');

  Future<List<RainAlertRule>> listAlerts() async {
    final data = await _api.getData('/v1/alerts');
    final alerts = data['alerts'];
    if (alerts is! List) throw const FormatException('Expected alerts list');
    return alerts
        .whereType<Map<String, dynamic>>()
        .map(RainAlertRule.fromJson)
        .toList(growable: false);
  }

  Future<RainAlertRule> createAlert(RainAlertInput input) async {
    final data = await _api.postData('/v1/alerts', input.toJson());
    return _readAlert(data);
  }

  Future<RainAlertRule> updateAlert(
    String alertId, {
    bool? enabled,
    int? leadMinutes,
    RainAlertIntensity? minimumIntensity,
    AlertQuietHoursInput? quietHours,
    AlertLocationInput? location,
  }) async {
    final data = await _api.patchData('/v1/alerts/$alertId', <String, Object?>{
      if (enabled != null) 'enabled': enabled,
      if (leadMinutes != null) 'leadMinutes': leadMinutes,
      if (minimumIntensity != null) 'minimumIntensity': minimumIntensity.name,
      if (quietHours != null) 'quietHours': quietHours.toJson(),
      if (location != null) 'location': location.toJson(),
    });
    return _readAlert(data);
  }

  Future<void> deleteAlert(String alertId) =>
      _api.delete('/v1/alerts/$alertId');

  RainAlertRule _readAlert(Map<String, dynamic> data) {
    final alert = data['alert'];
    if (alert is! Map<String, dynamic>) {
      throw const FormatException('Expected alert object');
    }
    return RainAlertRule.fromJson(alert);
  }
}
