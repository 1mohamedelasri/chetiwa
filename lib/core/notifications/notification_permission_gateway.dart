import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationAuthorization {
  notDetermined,
  authorized,
  denied,
  permanentlyDenied,
  restricted;

  bool get canSend => this == authorized;
  bool get needsSystemPrompt => this == notDetermined;
}

abstract interface class NotificationPermissionGateway {
  Future<NotificationAuthorization> status();

  Future<NotificationAuthorization> requestPermission();

  Future<bool> openSettings();
}

final class SystemNotificationPermissionGateway
    implements NotificationPermissionGateway {
  const SystemNotificationPermissionGateway();

  static const _applePermissionRequestedKey =
      'notifications.apple_permission_requested';

  @override
  Future<NotificationAuthorization> requestPermission() async {
    final result = await Permission.notification.request();
    if (Platform.isIOS || Platform.isMacOS) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_applePermissionRequestedKey, true);
    }
    return _map(result, applePermissionWasRequested: true);
  }

  @override
  Future<NotificationAuthorization> status() async {
    final result = await Permission.notification.status;
    var applePermissionWasRequested = false;
    if (Platform.isIOS || Platform.isMacOS) {
      final preferences = await SharedPreferences.getInstance();
      applePermissionWasRequested =
          preferences.getBool(_applePermissionRequestedKey) ?? false;
    }
    return _map(
      result,
      applePermissionWasRequested: applePermissionWasRequested,
    );
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  NotificationAuthorization _map(
    PermissionStatus status, {
    required bool applePermissionWasRequested,
  }) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => NotificationAuthorization.authorized,
    PermissionStatus.denied
        when (Platform.isIOS || Platform.isMacOS) &&
            applePermissionWasRequested =>
      NotificationAuthorization.denied,
    PermissionStatus.denied => NotificationAuthorization.notDetermined,
    PermissionStatus.permanentlyDenied =>
      NotificationAuthorization.permanentlyDenied,
    PermissionStatus.restricted => NotificationAuthorization.restricted,
    PermissionStatus.provisional => NotificationAuthorization.authorized,
  };
}

final class FixtureNotificationPermissionGateway
    implements NotificationPermissionGateway {
  FixtureNotificationPermissionGateway({
    NotificationAuthorization initial = NotificationAuthorization.notDetermined,
    this.requestResult = NotificationAuthorization.authorized,
    this.settingsResult = false,
  }) : _status = initial;

  NotificationAuthorization _status;
  final NotificationAuthorization requestResult;
  final bool settingsResult;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<NotificationAuthorization> requestPermission() async {
    requestCount += 1;
    return _status = requestResult;
  }

  @override
  Future<NotificationAuthorization> status() async => _status;

  @override
  Future<bool> openSettings() async {
    openSettingsCount += 1;
    return settingsResult;
  }
}
