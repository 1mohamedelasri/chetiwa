import 'dart:math';

import 'package:crypto/crypto.dart';

import 'device_alert_store.dart';

enum AlertRainIntensity {
  none,
  light,
  moderate,
  heavy;

  static AlertRainIntensity fromRate(double rateMmPerHour) =>
      switch (rateMmPerHour) {
        < 0.05 => none,
        < 0.5 => light,
        < 4 => moderate,
        _ => heavy,
      };

  static AlertRainIntensity parse(String value) =>
      AlertRainIntensity.values.byName(value);
}

final class RainNowcastSample {
  const RainNowcastSample({required this.time, required this.rateMmPerHour});

  final DateTime time;
  final double rateMmPerHour;

  AlertRainIntensity get intensity =>
      AlertRainIntensity.fromRate(rateMmPerHour);
}

final class RainAlertCell {
  const RainAlertCell({
    required this.key,
    required this.latitude,
    required this.longitude,
  });

  factory RainAlertCell.fromLocation(
    AlertLocation location, {
    double sizeDegrees = 0.05,
  }) {
    final latitudeIndex = ((location.latitude + 90) / sizeDegrees).floor();
    final longitudeIndex = ((location.longitude + 180) / sizeDegrees).floor();
    return RainAlertCell(
      key: '${sizeDegrees.toStringAsFixed(3)}:$latitudeIndex:$longitudeIndex',
      latitude: latitudeIndex * sizeDegrees - 90 + sizeDegrees / 2,
      longitude: longitudeIndex * sizeDegrees - 180 + sizeDegrees / 2,
    );
  }

  final String key;
  final double latitude;
  final double longitude;
}

enum RainAlertPollingMode { highFrequency, approaching, dry, retry }

/// Shared polling state for one geographic alert cell.
///
/// Cloud Run Jobs are stateless, so this small record lets the five-minute
/// scheduler wake cheaply while provider calls are skipped until they are
/// meteorologically useful. The record contains no device identifier or exact
/// user coordinate.
final class RainAlertCellSchedule {
  const RainAlertCellSchedule({
    required this.cellKey,
    required this.latitude,
    required this.longitude,
    required this.nextCheckAt,
    required this.lastCheckedAt,
    required this.mode,
  });

  final String cellKey;
  final double latitude;
  final double longitude;
  final DateTime nextCheckAt;
  final DateTime lastCheckedAt;
  final RainAlertPollingMode mode;
}

abstract interface class RainAlertNowcastProvider {
  Future<List<RainNowcastSample>> nowcast(RainAlertCell cell);
}

final class RainAlertState {
  const RainAlertState({
    required this.ownerHash,
    required this.alertId,
    this.rainExpected = false,
    this.lastIntensity = AlertRainIntensity.none,
    this.lastSentAt,
    this.dailyDate,
    this.dailyCount = 0,
    this.updatedAt,
  });

  final String ownerHash;
  final String alertId;
  final bool rainExpected;
  final AlertRainIntensity lastIntensity;
  final DateTime? lastSentAt;
  final String? dailyDate;
  final int dailyCount;
  final DateTime? updatedAt;

  RainAlertState copyWith({
    bool? rainExpected,
    AlertRainIntensity? lastIntensity,
    DateTime? lastSentAt,
    String? dailyDate,
    int? dailyCount,
    DateTime? updatedAt,
  }) => RainAlertState(
    ownerHash: ownerHash,
    alertId: alertId,
    rainExpected: rainExpected ?? this.rainExpected,
    lastIntensity: lastIntensity ?? this.lastIntensity,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    dailyDate: dailyDate ?? this.dailyDate,
    dailyCount: dailyCount ?? this.dailyCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

final class ActiveRainAlert {
  const ActiveRainAlert({
    required this.device,
    required this.rule,
    required this.state,
  });

  final DeviceRecord device;
  final AlertRuleRecord rule;
  final RainAlertState state;
}

final class AlertDeliveryDraft {
  const AlertDeliveryDraft({
    required this.eventId,
    required this.ownerHash,
    required this.alertId,
    required this.cellKey,
    required this.location,
    required this.intensity,
    required this.expectedAt,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
  });

  final String eventId;
  final String ownerHash;
  final String alertId;
  final String cellKey;
  final AlertLocation location;
  final AlertRainIntensity intensity;
  final DateTime expectedAt;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime expiresAt;
}

enum AlertDeliveryStatus { pending, sent, permanentFailure }

final class PendingAlertDelivery {
  const PendingAlertDelivery({
    required this.draft,
    required this.pushToken,
    required this.platform,
    required this.attempts,
    required this.nextAttemptAt,
  });

  final AlertDeliveryDraft draft;
  final String pushToken;
  final String platform;
  final int attempts;
  final DateTime nextAttemptAt;
}

abstract interface class RainAlertEngineStore {
  Future<bool> acquireLease({
    required String runId,
    required DateTime now,
    required DateTime expiresAt,
  });

  Future<void> releaseLease(String runId);

  Future<List<ActiveRainAlert>> listActiveAlerts();

  Future<List<RainAlertCellSchedule>> listDueCellSchedules({
    required DateTime now,
    int limit = 500,
  });

  Future<List<ActiveRainAlert>> listActiveAlertsForCell(String cellKey);

  Future<void> saveCellSchedule(RainAlertCellSchedule schedule);

  Future<void> deleteCellSchedule(String cellKey);

  Future<void> saveState(RainAlertState state);

  /// Returns false when the deterministic event already exists.
  Future<bool> enqueueDelivery(AlertDeliveryDraft delivery);

  Future<List<PendingAlertDelivery>> listPendingDeliveries({int limit = 500});

  Future<void> markDeliverySent(String eventId, DateTime sentAt);

  Future<void> retryDelivery(
    String eventId, {
    required int attempts,
    required DateTime nextAttemptAt,
  });

  Future<void> failDelivery(String eventId, String reason);

  Future<void> disableDeviceToken(String ownerHash);
}

enum PushSendOutcome { sent, invalidToken, transientFailure, permanentFailure }

abstract interface class RainAlertPushSender {
  Future<PushSendOutcome> send(PendingAlertDelivery delivery);
}

typedef LocalTimeResolver = DateTime Function(DateTime utc, String timeZone);

final class RainAlertEngine {
  RainAlertEngine({
    required RainAlertEngineStore store,
    required RainAlertNowcastProvider provider,
    required LocalTimeResolver localTime,
    DateTime Function()? now,
    this.maximumConcurrentCells = 8,
    this.cooldown = const Duration(minutes: 120),
    this.maximumAlertsPerLocalDay = 6,
    this.enqueueDeliveries = true,
  }) : _store = store,
       _provider = provider,
       _localTime = localTime,
       _now = now ?? DateTime.now;

  final RainAlertEngineStore _store;
  final RainAlertNowcastProvider _provider;
  final LocalTimeResolver _localTime;
  final DateTime Function() _now;
  final int maximumConcurrentCells;
  final Duration cooldown;
  final int maximumAlertsPerLocalDay;
  final bool enqueueDeliveries;

  Future<RainAlertRunReport> run() async {
    final startedAt = _now().toUtc();
    final slot = startedAt.millisecondsSinceEpoch ~/ 300000;
    final runId = 'rain-$slot';
    final acquired = await _store.acquireLease(
      runId: runId,
      now: startedAt,
      expiresAt: startedAt.add(const Duration(minutes: 10)),
    );
    if (!acquired) {
      return RainAlertRunReport(runId: runId, skippedBecauseLocked: true);
    }

    var cellsEvaluated = 0;
    var cellsSkipped = 0;
    var providerFailures = 0;
    var alertsEvaluated = 0;
    var deliveriesProposed = 0;
    var deliveriesEnqueued = 0;
    try {
      final dueSchedules = await _store.listDueCellSchedules(now: startedAt);
      final byCell =
          <String, ({RainAlertCell cell, List<ActiveRainAlert> alerts})>{};
      var activeAlerts = 0;
      for (final schedule in dueSchedules) {
        final alerts = await _store.listActiveAlertsForCell(schedule.cellKey);
        final eligible = alerts
            .where(
              (alert) =>
                  alert.device.notificationsEnabled &&
                  alert.device.expiresAt.isAfter(startedAt) &&
                  alert.device.pushToken != null &&
                  alert.device.pushToken!.isNotEmpty,
            )
            .toList(growable: false);
        if (eligible.isEmpty) {
          await _store.deleteCellSchedule(schedule.cellKey);
          continue;
        }
        activeAlerts += eligible.length;
        byCell[schedule.cellKey] = (
          cell: RainAlertCell(
            key: schedule.cellKey,
            latitude: schedule.latitude,
            longitude: schedule.longitude,
          ),
          alerts: eligible,
        );
      }

      final groups = byCell.values.toList(growable: false);
      for (
        var offset = 0;
        offset < groups.length;
        offset += maximumConcurrentCells
      ) {
        final end = min(offset + maximumConcurrentCells, groups.length);
        final results = await Future.wait(
          groups.sublist(offset, end).map((group) async {
            try {
              final samples = await _provider.nowcast(group.cell);
              var evaluated = 0;
              var proposed = 0;
              var enqueued = 0;
              for (final alert in group.alerts) {
                evaluated += 1;
                final decision = await _evaluate(
                  alert,
                  cell: group.cell,
                  samples: samples,
                  now: startedAt,
                );
                if (decision.proposed) proposed += 1;
                if (decision.enqueued) enqueued += 1;
              }
              final schedule = _nextCellSchedule(
                group.cell,
                alerts: group.alerts,
                samples: samples,
                now: startedAt,
              );
              try {
                await _store.saveCellSchedule(schedule);
              } on Object {
                // Polling state is a cost optimization, never a reason to
                // suppress an otherwise valid alert evaluation.
              }
              return (
                failed: false,
                evaluated: evaluated,
                proposed: proposed,
                enqueued: enqueued,
                deferred: _deferredCronRuns(schedule, startedAt),
              );
            } on Object {
              try {
                await _store.saveCellSchedule(
                  RainAlertCellSchedule(
                    cellKey: group.cell.key,
                    latitude: group.cell.latitude,
                    longitude: group.cell.longitude,
                    lastCheckedAt: startedAt,
                    nextCheckAt: startedAt.add(const Duration(minutes: 15)),
                    mode: RainAlertPollingMode.retry,
                  ),
                );
              } on Object {
                // A failed retry-state write only causes an earlier retry.
              }
              return (
                failed: true,
                evaluated: 0,
                proposed: 0,
                enqueued: 0,
                deferred: 2,
              );
            }
          }),
        );
        cellsEvaluated += results.length;
        providerFailures += results.where((result) => result.failed).length;
        alertsEvaluated += results.fold(
          0,
          (sum, result) => sum + result.evaluated,
        );
        deliveriesProposed += results.fold(
          0,
          (sum, result) => sum + result.proposed,
        );
        deliveriesEnqueued += results.fold(
          0,
          (sum, result) => sum + result.enqueued,
        );
        cellsSkipped += results.fold(0, (sum, result) => sum + result.deferred);
      }

      return RainAlertRunReport(
        runId: runId,
        activeAlerts: activeAlerts,
        cellsEvaluated: cellsEvaluated,
        cellsSkipped: cellsSkipped,
        providerFailures: providerFailures,
        alertsEvaluated: alertsEvaluated,
        deliveriesProposed: deliveriesProposed,
        deliveriesEnqueued: deliveriesEnqueued,
      );
    } finally {
      await _store.releaseLease(runId);
    }
  }

  RainAlertCellSchedule _nextCellSchedule(
    RainAlertCell cell, {
    required List<ActiveRainAlert> alerts,
    required List<RainNowcastSample> samples,
    required DateTime now,
  }) {
    final usable =
        samples
            .where(
              (sample) => !sample.time.isBefore(
                now.subtract(const Duration(minutes: 2)),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.time.compareTo(right.time));
    if (usable.isEmpty) {
      return RainAlertCellSchedule(
        cellKey: cell.key,
        latitude: cell.latitude,
        longitude: cell.longitude,
        lastCheckedAt: now,
        nextCheckAt: now.add(const Duration(minutes: 15)),
        mode: RainAlertPollingMode.retry,
      );
    }

    final maximumLeadMinutes = alerts.fold<int>(
      5,
      (value, alert) => max(value, alert.rule.leadMinutes),
    );
    final minimumIntensity = alerts.fold<AlertRainIntensity>(
      AlertRainIntensity.heavy,
      (value, alert) {
        final candidate = AlertRainIntensity.parse(alert.rule.minimumIntensity);
        return candidate.index < value.index ? candidate : value;
      },
    );
    final firstRain = usable.cast<RainNowcastSample?>().firstWhere(
      (sample) => sample!.intensity.index >= minimumIntensity.index,
      orElse: () => null,
    );

    if (firstRain != null) {
      final untilRain = firstRain.time.difference(now);
      final highFrequencyWindow = Duration(minutes: maximumLeadMinutes + 10);
      if (untilRain <= highFrequencyWindow) {
        return RainAlertCellSchedule(
          cellKey: cell.key,
          latitude: cell.latitude,
          longitude: cell.longitude,
          lastCheckedAt: now,
          nextCheckAt: now.add(const Duration(minutes: 5)),
          mode: RainAlertPollingMode.highFrequency,
        );
      }
      final desiredDelay = untilRain - highFrequencyWindow;
      final delay = desiredDelay < const Duration(minutes: 10)
          ? const Duration(minutes: 10)
          : desiredDelay > const Duration(minutes: 30)
          ? const Duration(minutes: 30)
          : desiredDelay;
      return RainAlertCellSchedule(
        cellKey: cell.key,
        latitude: cell.latitude,
        longitude: cell.longitude,
        lastCheckedAt: now,
        nextCheckAt: now.add(delay),
        mode: RainAlertPollingMode.approaching,
      );
    }

    final horizon = usable.last.time.difference(now);
    final delay = switch (horizon) {
      >= const Duration(hours: 4) => const Duration(hours: 2),
      >= const Duration(hours: 2) => const Duration(hours: 1),
      >= const Duration(minutes: 55) => const Duration(minutes: 15),
      _ => const Duration(minutes: 10),
    };
    return RainAlertCellSchedule(
      cellKey: cell.key,
      latitude: cell.latitude,
      longitude: cell.longitude,
      lastCheckedAt: now,
      nextCheckAt: now.add(delay),
      mode: RainAlertPollingMode.dry,
    );
  }

  static int _deferredCronRuns(RainAlertCellSchedule schedule, DateTime now) {
    final slots = schedule.nextCheckAt.difference(now).inMinutes ~/ 5;
    return max(0, slots - 1);
  }

  Future<({bool proposed, bool enqueued})> _evaluate(
    ActiveRainAlert alert, {
    required RainAlertCell cell,
    required List<RainNowcastSample> samples,
    required DateTime now,
  }) async {
    final cutoff = now.add(Duration(minutes: alert.rule.leadMinutes));
    final minimum = AlertRainIntensity.parse(alert.rule.minimumIntensity);
    final eligible =
        samples
            .where(
              (sample) =>
                  !sample.time.isBefore(
                    now.subtract(const Duration(minutes: 2)),
                  ) &&
                  !sample.time.isAfter(cutoff) &&
                  sample.intensity.index >= minimum.index,
            )
            .toList(growable: false)
          ..sort((left, right) => left.time.compareTo(right.time));
    final first = eligible.isEmpty ? null : eligible.first;
    final strongest = eligible.fold<AlertRainIntensity>(
      AlertRainIntensity.none,
      (value, sample) =>
          sample.intensity.index > value.index ? sample.intensity : value,
    );
    final rainExpected = first != null;
    final localNow = _localTime(now, alert.device.timeZone);
    final dailyDate = _dateKey(localNow);
    final previousDailyCount = alert.state.dailyDate == dailyDate
        ? alert.state.dailyCount
        : 0;
    final transition = rainExpected && !alert.state.rainExpected;
    final intensifiedToHeavy =
        rainExpected &&
        strongest == AlertRainIntensity.heavy &&
        alert.state.lastIntensity.index < AlertRainIntensity.heavy.index;
    final cooldownComplete =
        alert.state.lastSentAt == null ||
        now.difference(alert.state.lastSentAt!) >= cooldown;
    final outsideQuietHours = !_isQuietTime(localNow, alert.rule.quietHours);
    final maySend =
        (transition || intensifiedToHeavy) &&
        cooldownComplete &&
        outsideQuietHours &&
        previousDailyCount < maximumAlertsPerLocalDay;

    var enqueued = false;
    var dailyCount = previousDailyCount;
    var lastSentAt = alert.state.lastSentAt;
    if (maySend && enqueueDeliveries) {
      final eventId = _eventId(
        alert,
        expectedAt: first.time,
        intensity: strongest,
      );
      final french = alert.device.locale == 'fr';
      final expectedLocalTime = _hourMinute(
        _localTime(first.time, alert.device.timeZone),
      );
      enqueued = await _store.enqueueDelivery(
        AlertDeliveryDraft(
          eventId: eventId,
          ownerHash: alert.device.ownerHash,
          alertId: alert.rule.id,
          cellKey: cell.key,
          location: alert.rule.location,
          intensity: strongest,
          expectedAt: first.time,
          title: french ? 'Pluie bientôt' : 'Rain soon',
          body: french
              ? '${_frenchIntensity(strongest)} vers $expectedLocalTime à ${alert.rule.location.label}'
              : '${_englishIntensity(strongest)} rain around $expectedLocalTime in ${alert.rule.location.label}',
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 30)),
        ),
      );
      if (enqueued) {
        dailyCount += 1;
        lastSentAt = now;
      }
    }

    final nextState = alert.state.copyWith(
      rainExpected: rainExpected,
      lastIntensity: rainExpected ? strongest : AlertRainIntensity.none,
      lastSentAt: lastSentAt,
      dailyDate: enqueued ? dailyDate : alert.state.dailyDate,
      dailyCount: enqueued ? dailyCount : alert.state.dailyCount,
      updatedAt: now,
    );
    if (_stateChanged(alert.state, nextState)) {
      await _store.saveState(nextState);
    }
    return (proposed: maySend, enqueued: enqueued);
  }

  static bool _stateChanged(RainAlertState before, RainAlertState after) =>
      before.rainExpected != after.rainExpected ||
      before.lastIntensity != after.lastIntensity ||
      before.lastSentAt != after.lastSentAt ||
      before.dailyDate != after.dailyDate ||
      before.dailyCount != after.dailyCount;

  String _eventId(
    ActiveRainAlert alert, {
    required DateTime expectedAt,
    required AlertRainIntensity intensity,
  }) {
    final episodeSlot = expectedAt.toUtc().millisecondsSinceEpoch ~/ 300000;
    return sha256
        .convert(
          '${alert.device.ownerHash}:${alert.rule.id}:$episodeSlot:${intensity.name}'
              .codeUnits,
        )
        .toString()
        .substring(0, 40);
  }

  static bool _isQuietTime(DateTime local, QuietHours quietHours) {
    if (!quietHours.enabled) return false;
    final current = local.hour * 60 + local.minute;
    final start = _minutes(quietHours.start);
    final end = _minutes(quietHours.end);
    return start <= end
        ? current >= start && current < end
        : current >= start || current < end;
  }

  static int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _hourMinute(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static String _frenchIntensity(AlertRainIntensity value) => switch (value) {
    AlertRainIntensity.none || AlertRainIntensity.light => 'Pluie faible',
    AlertRainIntensity.moderate => 'Pluie modérée',
    AlertRainIntensity.heavy => 'Forte pluie',
  };

  static String _englishIntensity(AlertRainIntensity value) => switch (value) {
    AlertRainIntensity.none || AlertRainIntensity.light => 'Light',
    AlertRainIntensity.moderate => 'Moderate',
    AlertRainIntensity.heavy => 'Heavy',
  };
}

final class RainAlertPushDispatcher {
  RainAlertPushDispatcher({
    required RainAlertEngineStore store,
    required RainAlertPushSender sender,
    DateTime Function()? now,
    this.maximumAttempts = 5,
  }) : _store = store,
       _sender = sender,
       _now = now ?? DateTime.now;

  final RainAlertEngineStore _store;
  final RainAlertPushSender _sender;
  final DateTime Function() _now;
  final int maximumAttempts;

  Future<PushDispatchReport> flush() async {
    final now = _now().toUtc();
    final deliveries = await _store.listPendingDeliveries();
    var sent = 0;
    var retried = 0;
    var failed = 0;
    var invalidTokens = 0;
    for (final delivery in deliveries) {
      if (delivery.nextAttemptAt.isAfter(now) ||
          !delivery.draft.expiresAt.isAfter(now)) {
        if (!delivery.draft.expiresAt.isAfter(now)) {
          await _store.failDelivery(delivery.draft.eventId, 'expired');
          failed += 1;
        }
        continue;
      }
      final outcome = await _sender.send(delivery);
      switch (outcome) {
        case PushSendOutcome.sent:
          await _store.markDeliverySent(delivery.draft.eventId, now);
          sent += 1;
        case PushSendOutcome.invalidToken:
          await _store.disableDeviceToken(delivery.draft.ownerHash);
          await _store.failDelivery(delivery.draft.eventId, 'invalid_token');
          invalidTokens += 1;
          failed += 1;
        case PushSendOutcome.permanentFailure:
          await _store.failDelivery(delivery.draft.eventId, 'fcm_rejected');
          failed += 1;
        case PushSendOutcome.transientFailure:
          final attempts = delivery.attempts + 1;
          if (attempts >= maximumAttempts) {
            await _store.failDelivery(
              delivery.draft.eventId,
              'retry_exhausted',
            );
            failed += 1;
          } else {
            final seconds = min(900, 30 * pow(2, attempts - 1).toInt());
            await _store.retryDelivery(
              delivery.draft.eventId,
              attempts: attempts,
              nextAttemptAt: now.add(Duration(seconds: seconds)),
            );
            retried += 1;
          }
      }
    }
    return PushDispatchReport(
      pending: deliveries.length,
      sent: sent,
      retried: retried,
      failed: failed,
      invalidTokens: invalidTokens,
    );
  }
}

final class RainAlertRunReport {
  const RainAlertRunReport({
    required this.runId,
    this.skippedBecauseLocked = false,
    this.activeAlerts = 0,
    this.cellsEvaluated = 0,
    this.cellsSkipped = 0,
    this.providerFailures = 0,
    this.alertsEvaluated = 0,
    this.deliveriesProposed = 0,
    this.deliveriesEnqueued = 0,
  });

  final String runId;
  final bool skippedBecauseLocked;
  final int activeAlerts;
  final int cellsEvaluated;
  final int cellsSkipped;
  final int providerFailures;
  final int alertsEvaluated;
  final int deliveriesProposed;
  final int deliveriesEnqueued;
}

final class PushDispatchReport {
  const PushDispatchReport({
    required this.pending,
    required this.sent,
    required this.retried,
    required this.failed,
    required this.invalidTokens,
  });

  final int pending;
  final int sent;
  final int retried;
  final int failed;
  final int invalidTokens;
}
