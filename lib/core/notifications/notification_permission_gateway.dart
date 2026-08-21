import 'package:permission_handler/permission_handler.dart';

enum NotificationAuthorization {
  notDetermined,
  authorized,
  denied,
  permanentlyDenied,
  restricted;

  bool get canSend => this == authorized;
  bool get needsSystemPrompt => this == notDetermined || this == denied;
}

abstract interface class NotificationPermissionGateway {
  Future<NotificationAuthorization> status();

  Future<NotificationAuthorization> requestPermission();

  Future<bool> openSettings();
}

final class SystemNotificationPermissionGateway
    implements NotificationPermissionGateway {
  const SystemNotificationPermissionGateway();

  @override
  Future<NotificationAuthorization> requestPermission() async =>
      _map(await Permission.notification.request());

  @override
  Future<NotificationAuthorization> status() async =>
      _map(await Permission.notification.status);

  @override
  Future<bool> openSettings() => openAppSettings();

  NotificationAuthorization _map(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => NotificationAuthorization.authorized,
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
  }) : _status = initial;

  NotificationAuthorization _status;
  final NotificationAuthorization requestResult;

  @override
  Future<NotificationAuthorization> requestPermission() async =>
      _status = requestResult;

  @override
  Future<NotificationAuthorization> status() async => _status;

  @override
  Future<bool> openSettings() async => false;
}
