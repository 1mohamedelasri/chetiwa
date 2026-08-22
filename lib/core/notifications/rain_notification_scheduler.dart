import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../time/weather_clock.dart';

final class RainNotification {
  const RainNotification({
    required this.scheduledAt,
    required this.timeZone,
    required this.locationLabel,
    required this.body,
  });

  final DateTime scheduledAt;
  final String timeZone;
  final String locationLabel;
  final String body;
}

abstract interface class RainNotificationScheduler {
  Future<void> schedule(RainNotification notification);

  Future<void> cancel();
}

final class SystemRainNotificationScheduler
    implements RainNotificationScheduler {
  SystemRainNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _notificationId = 4101;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);

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

  @override
  Future<void> schedule(RainNotification notification) async {
    await _initialize();
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
      payload: 'rain-alert',
    );
  }

  @override
  Future<void> cancel() async {
    await _initialize();
    await _plugin.cancel(_notificationId);
  }
}

final class FixtureRainNotificationScheduler
    implements RainNotificationScheduler {
  RainNotification? scheduled;

  @override
  Future<void> schedule(RainNotification notification) async {
    scheduled = notification;
  }

  @override
  Future<void> cancel() async {
    scheduled = null;
  }
}
