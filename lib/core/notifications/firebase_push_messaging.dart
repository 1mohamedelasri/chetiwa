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
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) _open(decoded);
        } on FormatException {
          // Ignore legacy/local payloads that are not navigation data.
        }
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
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
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) return null;
    }
    return _messaging.getToken();
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
    await _localNotifications.show(
      stableId,
      title,
      body,
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
      payload: jsonEncode(message.data),
    );
  }

  void _open(Map<String, dynamic> data) {
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
