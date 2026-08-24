import 'dart:io';

import 'package:googleapis/fcm/v1.dart' as fcm;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'provider_gateway.dart';
import 'rain_alert_engine.dart';

/// Uses LibreWXR point nowcast first and transparently falls back to the
/// normalized Open-Meteo 15-minute series for cells outside radar coverage or
/// during a transient LibreWXR outage.
final class ProviderRainAlertNowcast implements RainAlertNowcastProvider {
  const ProviderRainAlertNowcast(this._gateway);

  final ProviderGateway _gateway;

  @override
  Future<List<RainNowcastSample>> nowcast(RainAlertCell cell) async {
    try {
      final radar = await _gateway.radarPointNowcast(
        latitude: cell.latitude,
        longitude: cell.longitude,
      );
      final samples = _samples(radar['samples']);
      if (samples.isNotEmpty) return samples;
    } on Object {
      // The model fallback below keeps alerts working outside radar coverage
      // and when LibreWXR is temporarily unavailable.
    }
    final forecast = await _gateway.forecast(
      latitude: cell.latitude,
      longitude: cell.longitude,
    );
    return _samples(forecast['precipitation15m']);
  }

  static List<RainNowcastSample> _samples(Object? raw) {
    if (raw is! List) return const <RainNowcastSample>[];
    final samples = raw
        .whereType<Map>()
        .map((item) {
          final time = DateTime.tryParse(item['time']?.toString() ?? '');
          final rate = item['rainRateMmPerHour'] ?? item['rateMmPerHour'];
          if (time == null || rate is! num || rate.isNegative) return null;
          return RainNowcastSample(
            time: time.toUtc(),
            rateMmPerHour: rate.toDouble(),
          );
        })
        .whereType<RainNowcastSample>()
        .toList(growable: false);
    samples.sort((left, right) => left.time.compareTo(right.time));
    return samples;
  }
}

final class FirebaseRainAlertPushSender implements RainAlertPushSender {
  FirebaseRainAlertPushSender({
    required fcm.FirebaseCloudMessagingApi api,
    required String projectId,
    DateTime Function()? now,
    http.Client? ownedClient,
  }) : _api = api,
       _project = 'projects/$projectId',
       _now = now ?? DateTime.now,
       _ownedClient = ownedClient;

  static Future<FirebaseRainAlertPushSender> connect({
    required String projectId,
  }) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const <String>[
        fcm.FirebaseCloudMessagingApi.firebaseMessagingScope,
      ],
    );
    return FirebaseRainAlertPushSender(
      api: fcm.FirebaseCloudMessagingApi(client),
      projectId: projectId,
      ownedClient: client,
    );
  }

  final fcm.FirebaseCloudMessagingApi _api;
  final String _project;
  final DateTime Function() _now;
  final http.Client? _ownedClient;

  Future<void> close() async => _ownedClient?.close();

  @override
  Future<PushSendOutcome> send(PendingAlertDelivery delivery) async {
    final expiration =
        _now()
            .toUtc()
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch ~/
        1000;
    final locationKey = delivery.draft.cellKey.replaceAll(':', '-');
    try {
      await _api.projects.messages.send(
        fcm.SendMessageRequest(
          message: fcm.Message(
            token: delivery.pushToken,
            notification: fcm.Notification(
              title: delivery.draft.title,
              body: delivery.draft.body,
            ),
            data: <String, String>{
              'type': 'rain_alert',
              'eventId': delivery.draft.eventId,
              'alertId': delivery.draft.alertId,
              'section': 'radar',
              'locationLabel': delivery.draft.location.label,
              'latitude': delivery.draft.location.latitude.toString(),
              'longitude': delivery.draft.location.longitude.toString(),
              'locationTimeZone': delivery.draft.location.timeZone,
              'intensity': delivery.draft.intensity.name,
              'expectedAt': delivery.draft.expectedAt.toIso8601String(),
            },
            android: fcm.AndroidConfig(
              collapseKey: 'rain-$locationKey',
              priority: 'HIGH',
              ttl: '1800s',
              notification: fcm.AndroidNotification(
                channelId: 'rain_alerts',
                clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                defaultSound: true,
                tag: 'rain-$locationKey',
              ),
            ),
            apns: fcm.ApnsConfig(
              headers: <String, String>{
                'apns-priority': '10',
                'apns-expiration': '$expiration',
                'apns-collapse-id': 'rain-$locationKey',
              },
              payload: const <String, Object?>{
                'aps': <String, Object?>{'sound': 'default'},
              },
            ),
          ),
        ),
        _project,
      );
      return PushSendOutcome.sent;
    } on fcm.DetailedApiRequestError catch (error) {
      final diagnostic = error.jsonResponse.toString().toUpperCase();
      if (diagnostic.contains('UNREGISTERED') ||
          diagnostic.contains('SENDER_ID_MISMATCH')) {
        return PushSendOutcome.invalidToken;
      }
      if (error.status == 408 ||
          error.status == 429 ||
          error.status == 500 ||
          error.status == 502 ||
          error.status == 503 ||
          error.status == 504) {
        return PushSendOutcome.transientFailure;
      }
      return PushSendOutcome.permanentFailure;
    } on http.ClientException {
      return PushSendOutcome.transientFailure;
    } on SocketException {
      return PushSendOutcome.transientFailure;
    } on Object {
      return PushSendOutcome.transientFailure;
    }
  }
}
