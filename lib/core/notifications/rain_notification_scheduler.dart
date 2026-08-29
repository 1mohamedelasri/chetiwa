import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../location/coordinates.dart';
import '../time/weather_clock.dart';
import 'rain_alert_navigation_controller.dart';

final class RainNotification {
  const RainNotification({
    required this.scheduledAt,
    required this.timeZone,
    required this.locationLabel,
    required this.body,
    required this.eventId,
    required this.coordinates,
  });

  final DateTime scheduledAt;
  final String timeZone;
  final String locationLabel;
  final String body;
  final String eventId;
  final Coordinates coordinates;

  Map<String, Object> get navigationData => <String, Object>{
    'type': 'rain_alert',
    'eventId': eventId,
    'locationLabel': locationLabel,
    'latitude': coordinates.latitude,
    'longitude': coordinates.longitude,
    'section': 'radar',
  };
}

abstract interface class RainNotificationScheduler {
  Future<void> initialize();

  Future<void> schedule(RainNotification notification);

  Future<void> cancel();
}

final class SystemRainNotificationScheduler
    implements RainNotificationScheduler {
  SystemRainNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    RainAlertNavigationController? navigation,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _navigation = navigation;

  static const _notificationId = 4101;
  final FlutterLocalNotificationsPlugin _plugin;
  final RainAlertNavigationController? _navigation;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _openPayload(response.payload);
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _openPayload(launchDetails?.notificationResponse?.payload);
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'rain_alerts',
            'Alertes pluie',
            description: 'Prévisions locales de pluie à venir',
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  void _openPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;
      final official = OfficialAlertNavigationIntent.fromData(decoded);
      if (official != null) {
        _navigation?.openOfficial(official);
        return;
      }
      final intent = RainAlertNavigationIntent.fromData(decoded);
      if (intent != null) _navigation?.open(intent);
    } on FormatException {
      // Ignore notifications created by an older app version.
    }
  }

  @override
  Future<void> schedule(RainNotification notification) async {
    await initialize();
    final location = WeatherTimeZone.location(notification.timeZone);
    await _plugin.zonedSchedule(
      _notificationId,
      'Pluie bientôt à ${notification.locationLabel}',
      notification.body,
      tz.TZDateTime.from(notification.scheduledAt.toUtc(), location),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rain_alerts',
          'Alertes pluie',
          channelDescription: 'Prévisions locales de pluie à venir',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: jsonEncode(notification.navigationData),
    );
  }

  @override
  Future<void> cancel() async {
    await initialize();
    await _plugin.cancel(_notificationId);
  }
}

final class FixtureRainNotificationScheduler
    implements RainNotificationScheduler {
  RainNotification? scheduled;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> schedule(RainNotification notification) async {
    scheduled = notification;
  }

  @override
  Future<void> cancel() async {
    scheduled = null;
  }
}
