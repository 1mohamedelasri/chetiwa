import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/chetiwa_api_client.dart';
import '../../../core/notifications/firebase_push_messaging.dart';
import '../../alerts/data/chetiwa_alert_api.dart';

enum RemoteRainAlertSyncResult {
  registered,

  /// The server registration already exists, but could not be refreshed.
  /// Local scheduling must remain disabled until an explicit deactivation.
  retained,
  unavailable,
  failed,
}

abstract interface class RemoteRainAlertGateway {
  Stream<String> get tokenRefresh;

  Future<void> initialize();

  Future<RemoteRainAlertSyncResult> syncRule({
    required AlertLocationInput location,
    required int leadMinutes,
    required RainAlertIntensity minimumIntensity,
    required AlertQuietHoursInput quietHours,
  });

  Future<bool> deactivate();

  Future<void> dispose();
}

final class ChetiwaRemoteRainAlertGateway implements RemoteRainAlertGateway {
  ChetiwaRemoteRainAlertGateway({
    required ChetiwaAlertApi api,
    required PushMessagingGateway messaging,
    Future<String> Function()? phoneTimeZone,
    Future<String> Function()? appVersion,
    String Function()? platform,
    String Function()? locale,
  }) : _api = api,
       _messaging = messaging,
       _phoneTimeZone = phoneTimeZone ?? _systemPhoneTimeZone,
       _appVersion = appVersion ?? _systemAppVersion,
       _platform = platform ?? _systemPlatform,
       _locale = locale ?? _systemLocale;

  static const _activeKey = 'alerts.remote_active:v1';
  static const _pendingDeletionKey = 'alerts.remote_pending_deletion:v1';

  final ChetiwaAlertApi _api;
  final PushMessagingGateway _messaging;
  final Future<String> Function() _phoneTimeZone;
  final Future<String> Function() _appVersion;
  final String Function() _platform;
  final String Function() _locale;

  @override
  Stream<String> get tokenRefresh => _messaging.tokenRefresh;

  @override
  Future<void> initialize() async {
    await _messaging.initialize();
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_pendingDeletionKey) ?? false) {
      await deactivate();
    }
  }

  @override
  Future<RemoteRainAlertSyncResult> syncRule({
    required AlertLocationInput location,
    required int leadMinutes,
    required RainAlertIntensity minimumIntensity,
    required AlertQuietHoursInput quietHours,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final remoteWasActive = preferences.getBool(_activeKey) ?? false;
    try {
      if (!await _messaging.authorizationGranted()) {
        return remoteWasActive
            ? RemoteRainAlertSyncResult.retained
            : RemoteRainAlertSyncResult.unavailable;
      }
      final token = await _messaging.currentToken();
      if (token == null || token.isEmpty) {
        return remoteWasActive
            ? RemoteRainAlertSyncResult.retained
            : RemoteRainAlertSyncResult.unavailable;
      }
      await _api.registerDevice(
        platform: _platform(),
        locale: _locale(),
        timeZone: await _phoneTimeZone(),
        notificationsEnabled: true,
        pushToken: token,
        appVersion: await _appVersion(),
      );

      final input = RainAlertInput(
        location: location,
        leadMinutes: leadMinutes,
        minimumIntensity: minimumIntensity,
        quietHours: quietHours,
        enabled: true,
      );
      final existing = await _api.listAlerts();
      if (existing.isEmpty) {
        await _api.createAlert(input);
      } else {
        await _api.updateAlert(
          existing.first.id,
          enabled: true,
          leadMinutes: leadMinutes,
          minimumIntensity: minimumIntensity,
          quietHours: quietHours,
          location: location,
        );
        for (final staleRule in existing.skip(1)) {
          await _api.deleteAlert(staleRule.id);
        }
      }

      await Future.wait(<Future<bool>>[
        preferences.setBool(_activeKey, true),
        preferences.setBool(_pendingDeletionKey, false),
      ]);
      return RemoteRainAlertSyncResult.registered;
    } on Object {
      return remoteWasActive
          ? RemoteRainAlertSyncResult.retained
          : RemoteRainAlertSyncResult.failed;
    }
  }

  @override
  Future<bool> deactivate() async {
    final preferences = await SharedPreferences.getInstance();
    final knownRegistration =
        (preferences.getBool(_activeKey) ?? false) ||
        (preferences.getBool(_pendingDeletionKey) ?? false);
    if (!knownRegistration) return true;
    await preferences.setBool(_pendingDeletionKey, true);

    // Revoke delivery locally first; server cleanup may need a slow retry when
    // the phone is offline, but the device should stop accepting this token as
    // soon as possible.
    var tokenDeleted = false;
    try {
      await _messaging.disable();
      tokenDeleted = true;
    } on Object {
      tokenDeleted = false;
    }

    var serverDeleted = false;
    try {
      await _api.deleteDevice();
      serverDeleted = true;
    } on ChetiwaApiException catch (error) {
      serverDeleted = error.statusCode == 404;
    } on Object {
      serverDeleted = false;
    }

    final completed = serverDeleted && tokenDeleted;
    if (completed) {
      await Future.wait(<Future<bool>>[
        preferences.setBool(_activeKey, false),
        preferences.setBool(_pendingDeletionKey, false),
      ]);
    }
    return completed;
  }

  @override
  Future<void> dispose() => _messaging.dispose();

  static Future<String> _systemPhoneTimeZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  static Future<String> _systemAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  static String _systemPlatform() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'android';
  }

  static String _systemLocale() {
    final language = PlatformDispatcher.instance.locale.languageCode;
    return language == 'en' ? 'en' : 'fr';
  }
}

final class FixtureRemoteRainAlertGateway implements RemoteRainAlertGateway {
  FixtureRemoteRainAlertGateway({
    this.result = RemoteRainAlertSyncResult.registered,
  });

  RemoteRainAlertSyncResult result;
  int syncCount = 0;
  int deactivateCount = 0;
  final StreamController<String> _tokens = StreamController<String>.broadcast();

  @override
  Stream<String> get tokenRefresh => _tokens.stream;

  void emitToken(String token) => _tokens.add(token);

  @override
  Future<bool> deactivate() async {
    deactivateCount += 1;
    return true;
  }

  @override
  Future<void> dispose() => _tokens.close();

  @override
  Future<void> initialize() async {}

  @override
  Future<RemoteRainAlertSyncResult> syncRule({
    required AlertLocationInput location,
    required int leadMinutes,
    required RainAlertIntensity minimumIntensity,
    required AlertQuietHoursInput quietHours,
  }) async {
    syncCount += 1;
    return result;
  }
}
