import 'dart:math';

import 'api_exception.dart';

final class DeviceRegistration {
  const DeviceRegistration({
    required this.platform,
    required this.locale,
    required this.timeZone,
    required this.notificationsEnabled,
    this.pushToken,
    this.appVersion,
  });

  final String platform;
  final String locale;
  final String timeZone;
  final bool notificationsEnabled;
  final String? pushToken;
  final String? appVersion;
}

final class DeviceRecord {
  const DeviceRecord({
    required this.ownerHash,
    required this.platform,
    required this.locale,
    required this.timeZone,
    required this.notificationsEnabled,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.pushToken,
    this.appVersion,
  });

  final String ownerHash;
  final String platform;
  final String locale;
  final String timeZone;
  final bool notificationsEnabled;
  final String? pushToken;
  final String? appVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
}

final class AlertLocation {
  const AlertLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.timeZone,
  });

  final String label;
  final double latitude;
  final double longitude;
  final String timeZone;
}

final class QuietHours {
  const QuietHours({
    required this.enabled,
    required this.start,
    required this.end,
  });

  final bool enabled;
  final String start;
  final String end;
}

final class AlertRuleDraft {
  const AlertRuleDraft({
    required this.location,
    required this.leadMinutes,
    required this.minimumIntensity,
    required this.quietHours,
    required this.enabled,
  });

  final AlertLocation location;
  final int leadMinutes;
  final String minimumIntensity;
  final QuietHours quietHours;
  final bool enabled;
}

final class AlertRuleChanges {
  const AlertRuleChanges({
    this.location,
    this.leadMinutes,
    this.minimumIntensity,
    this.quietHours,
    this.enabled,
  });

  final AlertLocation? location;
  final int? leadMinutes;
  final String? minimumIntensity;
  final QuietHours? quietHours;
  final bool? enabled;

  bool get isEmpty =>
      location == null &&
      leadMinutes == null &&
      minimumIntensity == null &&
      quietHours == null &&
      enabled == null;
}

final class AlertRuleRecord {
  const AlertRuleRecord({
    required this.id,
    required this.ownerHash,
    required this.location,
    required this.leadMinutes,
    required this.minimumIntensity,
    required this.quietHours,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerHash;
  final AlertLocation location;
  final int leadMinutes;
  final String minimumIntensity;
  final QuietHours quietHours;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class DeviceAlertStore {
  Future<DeviceRecord> upsertDevice(
    String ownerHash,
    DeviceRegistration registration,
  );

  Future<bool> deleteDevice(String ownerHash);

  Future<List<AlertRuleRecord>> listAlerts(String ownerHash);

  Future<AlertRuleRecord> createAlert(String ownerHash, AlertRuleDraft draft);

  Future<AlertRuleRecord?> updateAlert(
    String ownerHash,
    String alertId,
    AlertRuleChanges changes,
  );

  Future<bool> deleteAlert(String ownerHash, String alertId);
}

final class InMemoryDeviceAlertStore implements DeviceAlertStore {
  InMemoryDeviceAlertStore({
    DateTime Function()? now,
    String Function()? idGenerator,
    this.maximumAlertsPerDevice = 5,
    this.maximumDevices = 10000,
  }) : _now = now ?? DateTime.now,
       _idGenerator = idGenerator ?? _secureId;

  final DateTime Function() _now;
  final String Function() _idGenerator;
  final int maximumAlertsPerDevice;
  final int maximumDevices;
  final Map<String, DeviceRecord> _devices = <String, DeviceRecord>{};
  final Map<String, Map<String, AlertRuleRecord>> _alerts =
      <String, Map<String, AlertRuleRecord>>{};

  @override
  Future<DeviceRecord> upsertDevice(
    String ownerHash,
    DeviceRegistration registration,
  ) async {
    final existing = _devices[ownerHash];
    if (existing == null && _devices.length >= maximumDevices) {
      throw const ApiException(
        statusCode: 503,
        code: 'device_capacity_reached',
        message: 'Device registration is temporarily unavailable',
      );
    }
    final instant = _now().toUtc();
    final record = DeviceRecord(
      ownerHash: ownerHash,
      platform: registration.platform,
      locale: registration.locale,
      timeZone: registration.timeZone,
      notificationsEnabled: registration.notificationsEnabled,
      pushToken: registration.notificationsEnabled
          ? registration.pushToken
          : null,
      appVersion: registration.appVersion,
      createdAt: existing?.createdAt ?? instant,
      updatedAt: instant,
      expiresAt: instant.add(const Duration(days: 180)),
    );
    _devices[ownerHash] = record;
    return record;
  }

  @override
  Future<bool> deleteDevice(String ownerHash) async {
    _alerts.remove(ownerHash);
    return _devices.remove(ownerHash) != null;
  }

  @override
  Future<List<AlertRuleRecord>> listAlerts(String ownerHash) async {
    _requireDevice(ownerHash);
    final records = _alerts[ownerHash]?.values.toList() ?? <AlertRuleRecord>[];
    records.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return records;
  }

  @override
  Future<AlertRuleRecord> createAlert(
    String ownerHash,
    AlertRuleDraft draft,
  ) async {
    _requireDevice(ownerHash);
    final deviceAlerts = _alerts.putIfAbsent(
      ownerHash,
      () => <String, AlertRuleRecord>{},
    );
    if (deviceAlerts.length >= maximumAlertsPerDevice) {
      throw ApiException(
        statusCode: 409,
        code: 'alert_limit_reached',
        message: 'A maximum of $maximumAlertsPerDevice alerts is allowed',
      );
    }
    final instant = _now().toUtc();
    String id;
    do {
      id = _idGenerator();
    } while (deviceAlerts.containsKey(id));
    final record = AlertRuleRecord(
      id: id,
      ownerHash: ownerHash,
      location: draft.location,
      leadMinutes: draft.leadMinutes,
      minimumIntensity: draft.minimumIntensity,
      quietHours: draft.quietHours,
      enabled: draft.enabled,
      createdAt: instant,
      updatedAt: instant,
    );
    deviceAlerts[id] = record;
    return record;
  }

  @override
  Future<AlertRuleRecord?> updateAlert(
    String ownerHash,
    String alertId,
    AlertRuleChanges changes,
  ) async {
    _requireDevice(ownerHash);
    final existing = _alerts[ownerHash]?[alertId];
    if (existing == null) return null;
    final record = AlertRuleRecord(
      id: existing.id,
      ownerHash: existing.ownerHash,
      location: changes.location ?? existing.location,
      leadMinutes: changes.leadMinutes ?? existing.leadMinutes,
      minimumIntensity: changes.minimumIntensity ?? existing.minimumIntensity,
      quietHours: changes.quietHours ?? existing.quietHours,
      enabled: changes.enabled ?? existing.enabled,
      createdAt: existing.createdAt,
      updatedAt: _now().toUtc(),
    );
    _alerts[ownerHash]![alertId] = record;
    return record;
  }

  @override
  Future<bool> deleteAlert(String ownerHash, String alertId) async {
    _requireDevice(ownerHash);
    return _alerts[ownerHash]?.remove(alertId) != null;
  }

  void _requireDevice(String ownerHash) {
    if (!_devices.containsKey(ownerHash)) {
      throw const ApiException(
        statusCode: 409,
        code: 'device_not_registered',
        message: 'Register this installation before managing alerts',
      );
    }
  }

  static String _secureId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
  }
}

final class UnavailableDeviceAlertStore implements DeviceAlertStore {
  const UnavailableDeviceAlertStore();

  Never _unavailable() => throw const ApiException(
    statusCode: 503,
    code: 'persistent_store_not_configured',
    message: 'Persistent device and alert storage is not configured',
  );

  @override
  Future<AlertRuleRecord> createAlert(
    String ownerHash,
    AlertRuleDraft draft,
  ) async => _unavailable();

  @override
  Future<bool> deleteAlert(String ownerHash, String alertId) async =>
      _unavailable();

  @override
  Future<bool> deleteDevice(String ownerHash) async => _unavailable();

  @override
  Future<List<AlertRuleRecord>> listAlerts(String ownerHash) async =>
      _unavailable();

  @override
  Future<AlertRuleRecord?> updateAlert(
    String ownerHash,
    String alertId,
    AlertRuleChanges changes,
  ) async => _unavailable();

  @override
  Future<DeviceRecord> upsertDevice(
    String ownerHash,
    DeviceRegistration registration,
  ) async => _unavailable();
}
