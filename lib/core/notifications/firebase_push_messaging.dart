import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import 'rain_alert_navigation_controller.dart';

@pragma('vm:entry-point')
Future<void> chetiwaFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

abstract interface class PushMessagingGateway {
  Future<void> initialize();

  Future<bool> authorizationGranted();

  Future<String?> currentToken();

  Stream<String> get tokenRefresh;

  Future<void> disable();

  Future<void> dispose();
}

final class FirebasePushMessagingGateway implements PushMessagingGateway {
  FirebasePushMessagingGateway({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    RainAlertNavigationController? navigation,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _navigation = navigation;

  static const _channel = AndroidNotificationChannel(
    'rain_alerts',
    'Alertes pluie',
    description: 'Prévisions locales de pluie à venir',
    importance: Importance.high,
  );
  static const _officialChannel = AndroidNotificationChannel(
    'official_weather_alerts',
    'Vigilance officielle',
    description: 'Vigilances départementales officielles Météo-France',
    importance: Importance.high,
  );

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final RainAlertNavigationController? _navigation;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_officialChannel);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false,
      sound: true,
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _presentForegroundMessage,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _open(message.data),
    );
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) _open(initialMessage.data);
    _initialized = true;
  }

  @override
  Future<bool> authorizationGranted() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> currentToken() async {
    await _messaging.setAutoInitEnabled(true);
    if (Platform.isIOS) {
      // FCM cannot mint a usable iOS token before APNs has registered the app.
      final apnsToken = await _waitForApnsToken();
      if (apnsToken == null || apnsToken.isEmpty) return null;
    }
    return _messaging.getToken();
  }

  Future<String?> _waitForApnsToken() async {
    const attempts = 20;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      final token = await _messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) return token;
      if (attempt < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return null;
  }

  @override
  Future<void> disable() async {
    await _messaging.deleteToken();
    await _messaging.setAutoInitEnabled(false);
  }

  Future<void> _presentForegroundMessage(RemoteMessage message) async {
    // iOS already presents foreground notifications through the options above.
    // Showing another local notification here would duplicate the same event.
    if (Platform.isIOS) return;
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'];
    final body = notification?.body ?? message.data['body'];
    if (title == null && body == null) return;
    final stableId =
        (message.messageId ?? '${title ?? ''}|${body ?? ''}').hashCode &
        0x7fffffff;
    final official = message.data['type'] == 'official_weather_alert';
    final channel = official ? _officialChannel : _channel;
    await _localNotifications.show(
      stableId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _open(Map<String, dynamic> data) {
    final official = OfficialAlertNavigationIntent.fromData(data);
    if (official != null) {
      _navigation?.openOfficial(official);
      return;
    }
    final intent = RainAlertNavigationIntent.fromData(data);
    if (intent != null) _navigation?.open(intent);
  }

  @override
  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}

final class FixturePushMessagingGateway implements PushMessagingGateway {
  FixturePushMessagingGateway({
    this.authorized = true,
    this.token = 'fixture-push-token',
  });

  bool authorized;
  String? token;
  bool disabled = false;
  final StreamController<String> _tokenRefresh =
      StreamController<String>.broadcast();

  @override
  Stream<String> get tokenRefresh => _tokenRefresh.stream;

  void emitToken(String value) {
    token = value;
    _tokenRefresh.add(value);
  }

  @override
  Future<bool> authorizationGranted() async => authorized;

  @override
  Future<String?> currentToken() async => token;

  @override
  Future<void> disable() async {
    disabled = true;
    token = null;
  }

  @override
  Future<void> dispose() => _tokenRefresh.close();

  @override
  Future<void> initialize() async {}
}
