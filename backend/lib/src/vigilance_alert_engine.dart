import 'dart:math';

import 'package:crypto/crypto.dart';

import 'device_alert_store.dart';

String vigilanceSettingsFingerprint(VigilanceAlertSettings settings) {
  final phenomena = settings.phenomena.map((value) => value.id).toList()
    ..sort();
  final value =
      '${settings.enabled}|${settings.minimumLevel.name}|'
      '${settings.departmentCode}|${phenomena.join(',')}';
  return sha256.convert(value.codeUnits).toString();
}

final class VigilanceEvent {
  const VigilanceEvent({
    required this.departmentCode,
    required this.phenomenon,
    required this.level,
    required this.beginsAt,
    required this.endsAt,
  });

  final String departmentCode;
  final VigilancePhenomenon phenomenon;
  final VigilanceLevel level;
  final DateTime beginsAt;
  final DateTime endsAt;
}

final class VigilanceSnapshot {
  const VigilanceSnapshot({
    required this.snapshotId,
    required this.productAt,
    required this.events,
  });

  final String snapshotId;
  final DateTime productAt;
  final List<VigilanceEvent> events;
}

abstract interface class VigilanceProvider {
  Future<VigilanceSnapshot> current();
}

final class VigilancePhenomenonState {
  const VigilancePhenomenonState({
    required this.level,
    required this.beginsAt,
    required this.endsAt,
  });

  final VigilanceLevel level;
  final DateTime beginsAt;
  final DateTime endsAt;
}

final class VigilanceAlertState {
  const VigilanceAlertState({
    required this.ownerHash,
    required this.alertId,
    this.phenomena = const <VigilancePhenomenon, VigilancePhenomenonState>{},
    this.productAt,
    this.updatedAt,
    this.settingsFingerprint,
  });

  final String ownerHash;
  final String alertId;
  final Map<VigilancePhenomenon, VigilancePhenomenonState> phenomena;
  final DateTime? productAt;
  final DateTime? updatedAt;
  final String? settingsFingerprint;
}

final class ActiveVigilanceAlert {
  const ActiveVigilanceAlert({
    required this.device,
    required this.rule,
    required this.state,
  });

  final DeviceRecord device;
  final AlertRuleRecord rule;
  final VigilanceAlertState state;
}

enum VigilanceDeliveryKind { started, changed, ended }

final class VigilanceDeliveryDraft {
  const VigilanceDeliveryDraft({
    required this.eventId,
    required this.ownerHash,
    required this.alertId,
    required this.departmentCode,
    required this.departmentName,
    required this.phenomenon,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    required this.settingsFingerprint,
    this.level,
    this.beginsAt,
    this.endsAt,
  });

  final String eventId;
  final String ownerHash;
  final String alertId;
  final String departmentCode;
  final String departmentName;
  final VigilancePhenomenon phenomenon;
  final VigilanceDeliveryKind kind;
  final VigilanceLevel? level;
  final DateTime? beginsAt;
  final DateTime? endsAt;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String settingsFingerprint;
}

final class PendingVigilanceDelivery {
  const PendingVigilanceDelivery({
    required this.draft,
    required this.pushToken,
    required this.platform,
    required this.attempts,
    required this.nextAttemptAt,
  });

  final VigilanceDeliveryDraft draft;
  final String pushToken;
  final String platform;
  final int attempts;
  final DateTime nextAttemptAt;
}

abstract interface class VigilanceAlertStore {
  Future<List<ActiveVigilanceAlert>> listActiveVigilanceAlerts();

  Future<void> saveVigilanceState(VigilanceAlertState state);

  Future<bool> enqueueVigilanceDelivery(VigilanceDeliveryDraft delivery);

  Future<List<PendingVigilanceDelivery>> listPendingVigilanceDeliveries({
    int limit = 500,
  });

  Future<void> markVigilanceDeliverySent(String eventId, DateTime sentAt);

  Future<void> retryVigilanceDelivery(
    String eventId, {
    required int attempts,
    required DateTime nextAttemptAt,
  });

  Future<void> failVigilanceDelivery(String eventId, String reason);

  Future<void> disableDeviceToken(String ownerHash);
}

final class VigilanceRunReport {
  const VigilanceRunReport({
    required this.snapshotId,
    required this.activeAlerts,
    required this.alertsEvaluated,
    required this.deliveriesProposed,
    required this.deliveriesEnqueued,
  });

  final String snapshotId;
  final int activeAlerts;
  final int alertsEvaluated;
  final int deliveriesProposed;
  final int deliveriesEnqueued;
}

final class VigilanceAlertEngine {
  VigilanceAlertEngine({
    required VigilanceAlertStore store,
    required VigilanceProvider provider,
    DateTime Function()? now,
    this.enqueueDeliveries = true,
    this.maximumProductAge = const Duration(hours: 26),
    this.maximumLookAhead = const Duration(hours: 48),
    int maximumConcurrentAlerts = 32,
  }) : _store = store,
       _provider = provider,
       _now = now ?? DateTime.now,
       maximumConcurrentAlerts = max(1, maximumConcurrentAlerts);

  final VigilanceAlertStore _store;
  final VigilanceProvider _provider;
  final DateTime Function() _now;
  final bool enqueueDeliveries;
  final Duration maximumProductAge;
  final Duration maximumLookAhead;
  final int maximumConcurrentAlerts;

  Future<VigilanceRunReport> run() async {
    final instant = _now().toUtc();
    final snapshot = await _provider.current();
    if (snapshot.productAt.isAfter(instant.add(const Duration(minutes: 10))) ||
        instant.difference(snapshot.productAt) > maximumProductAge) {
      throw StateError(
        'Meteo-France vigilance product is stale or future-dated',
      );
    }
    final alerts = (await _store.listActiveVigilanceAlerts())
        .where(
          (alert) =>
              alert.device.notificationsEnabled &&
              alert.device.expiresAt.isAfter(instant) &&
              alert.device.pushToken != null &&
              alert.device.pushToken!.isNotEmpty &&
              alert.rule.vigilance.enabled &&
              alert.rule.vigilance.departmentCode != null,
        )
        .toList(growable: false);
    var proposed = 0;
    var enqueued = 0;
    for (
      var offset = 0;
      offset < alerts.length;
      offset += maximumConcurrentAlerts
    ) {
      final end = min(offset + maximumConcurrentAlerts, alerts.length);
      final results = await Future.wait(
        alerts
            .sublist(offset, end)
            .map((alert) => _evaluateAlert(snapshot, alert, instant)),
      );
      for (final result in results) {
        proposed += result.proposed;
        enqueued += result.enqueued;
      }
    }
    return VigilanceRunReport(
      snapshotId: snapshot.snapshotId,
      activeAlerts: alerts.length,
      alertsEvaluated: alerts.length,
      deliveriesProposed: proposed,
      deliveriesEnqueued: enqueued,
    );
  }

  Future<({int proposed, int enqueued})> _evaluateAlert(
    VigilanceSnapshot snapshot,
    ActiveVigilanceAlert alert,
    DateTime instant,
  ) async {
    final current = _currentEvents(snapshot, alert, instant);
    final settingsFingerprint = vigilanceSettingsFingerprint(
      alert.rule.vigilance,
    );
    final previous = alert.state.settingsFingerprint == settingsFingerprint
        ? alert.state.phenomena
        : const <VigilancePhenomenon, VigilancePhenomenonState>{};
    var proposed = 0;
    var enqueued = 0;
    for (final phenomenon in <VigilancePhenomenon>{
      ...previous.keys,
      ...current.keys,
    }) {
      final before = previous[phenomenon];
      final after = current[phenomenon];
      final kind = _deliveryKind(before, after, instant);
      if (kind == null) continue;
      proposed += 1;
      if (!enqueueDeliveries) continue;
      final draft = _delivery(alert, phenomenon, before, after, kind, instant);
      if (await _store.enqueueVigilanceDelivery(draft)) enqueued += 1;
    }
    // Shadow mode must not acknowledge an event as delivered. Otherwise an
    // orange/red warning already active during rollout would be skipped when
    // real sending is enabled later.
    if (enqueueDeliveries) {
      await _store.saveVigilanceState(
        VigilanceAlertState(
          ownerHash: alert.rule.ownerHash,
          alertId: alert.rule.id,
          phenomena: current,
          productAt: snapshot.productAt,
          updatedAt: instant,
          settingsFingerprint: settingsFingerprint,
        ),
      );
    }
    return (proposed: proposed, enqueued: enqueued);
  }

  Map<VigilancePhenomenon, VigilancePhenomenonState> _currentEvents(
    VigilanceSnapshot snapshot,
    ActiveVigilanceAlert alert,
    DateTime instant,
  ) {
    final settings = alert.rule.vigilance;
    final candidates = snapshot.events.where(
      (event) =>
          event.departmentCode == settings.departmentCode &&
          settings.phenomena.contains(event.phenomenon) &&
          event.level.colorId >= settings.minimumLevel.colorId &&
          event.endsAt.isAfter(instant) &&
          !event.beginsAt.isAfter(instant.add(maximumLookAhead)),
    );
    final selected = <VigilancePhenomenon, VigilancePhenomenonState>{};
    for (final event in candidates) {
      final existing = selected[event.phenomenon];
      final replace =
          existing == null ||
          event.level.colorId > existing.level.colorId ||
          (event.level == existing.level &&
              event.beginsAt.isBefore(existing.beginsAt));
      if (replace) {
        selected[event.phenomenon] = VigilancePhenomenonState(
          level: event.level,
          beginsAt: event.beginsAt,
          endsAt: event.endsAt,
        );
      }
    }
    return selected;
  }

  VigilanceDeliveryKind? _deliveryKind(
    VigilancePhenomenonState? before,
    VigilancePhenomenonState? after,
    DateTime instant,
  ) {
    if (before == null && after != null) return VigilanceDeliveryKind.started;
    if (before != null && after == null) return VigilanceDeliveryKind.ended;
    if (before == null || after == null) return null;
    if (before.level != after.level) return VigilanceDeliveryKind.changed;
    if (!before.endsAt.isAfter(instant) &&
        after.beginsAt.isAfter(before.endsAt)) {
      return VigilanceDeliveryKind.started;
    }
    return null;
  }

  VigilanceDeliveryDraft _delivery(
    ActiveVigilanceAlert alert,
    VigilancePhenomenon phenomenon,
    VigilancePhenomenonState? before,
    VigilancePhenomenonState? after,
    VigilanceDeliveryKind kind,
    DateTime instant,
  ) {
    final departmentCode = alert.rule.vigilance.departmentCode!;
    final departmentName =
        alert.rule.vigilance.departmentName ?? departmentCode;
    final level = after?.level;
    final eventKey = <Object?>[
      alert.rule.ownerHash,
      alert.rule.id,
      departmentCode,
      phenomenon.id,
      kind.name,
      level?.name ?? 'green',
      after?.beginsAt.toUtc().toIso8601String() ??
          before?.endsAt.toUtc().toIso8601String(),
    ].join('|');
    final eventId = sha256.convert(eventKey.codeUnits).toString();
    final copy = _copy(
      locale: alert.device.locale,
      departmentName: departmentName,
      phenomenon: phenomenon,
      level: level,
      kind: kind,
      beginsAt: after?.beginsAt,
    );
    final validityEnd = after?.endsAt ?? instant.add(const Duration(hours: 6));
    return VigilanceDeliveryDraft(
      eventId: eventId,
      ownerHash: alert.rule.ownerHash,
      alertId: alert.rule.id,
      departmentCode: departmentCode,
      departmentName: departmentName,
      phenomenon: phenomenon,
      kind: kind,
      level: level,
      beginsAt: after?.beginsAt,
      endsAt: after?.endsAt,
      title: copy.title,
      body: copy.body,
      createdAt: instant,
      expiresAt: validityEnd.isAfter(instant)
          ? validityEnd
          : instant.add(const Duration(hours: 1)),
      settingsFingerprint: vigilanceSettingsFingerprint(alert.rule.vigilance),
    );
  }

  ({String title, String body}) _copy({
    required String locale,
    required String departmentName,
    required VigilancePhenomenon phenomenon,
    required VigilanceLevel? level,
    required VigilanceDeliveryKind kind,
    required DateTime? beginsAt,
  }) {
    final french = locale != 'en';
    if (kind == VigilanceDeliveryKind.ended) {
      return (
        title: french ? 'Vigilance terminée' : 'Warning ended',
        body: french
            ? '${_phenomenonLabel(phenomenon, true)} : fin de la vigilance dans $departmentName.'
            : '${_phenomenonLabel(phenomenon, false)} warning ended in $departmentName.',
      );
    }
    final levelLabel = french
        ? switch (level!) {
            VigilanceLevel.yellow => 'jaune',
            VigilanceLevel.orange => 'orange',
            VigilanceLevel.red => 'rouge',
          }
        : level!.name;
    final future = beginsAt != null && beginsAt.isAfter(_now().toUtc());
    return (
      title: french
          ? 'Vigilance $levelLabel · $departmentName'
          : '${levelLabel[0].toUpperCase()}${levelLabel.substring(1)} warning · $departmentName',
      body: french
          ? '${_phenomenonLabel(phenomenon, true)}${future ? ' à venir' : ''}. Consultez les consignes officielles Météo-France.'
          : '${_phenomenonLabel(phenomenon, false)}${future ? ' expected' : ''}. Check the official Météo-France guidance.',
    );
  }

  String _phenomenonLabel(VigilancePhenomenon value, bool french) =>
      switch ((value, french)) {
        (VigilancePhenomenon.wind, true) => 'Vent',
        (VigilancePhenomenon.rainFlood, true) => 'Pluie-inondation',
        (VigilancePhenomenon.thunderstorms, true) => 'Orages',
        (VigilancePhenomenon.floods, true) => 'Crues',
        (VigilancePhenomenon.snowIce, true) => 'Neige-verglas',
        (VigilancePhenomenon.heatwave, true) => 'Canicule',
        (VigilancePhenomenon.extremeCold, true) => 'Grand froid',
        (VigilancePhenomenon.avalanches, true) => 'Avalanches',
        (VigilancePhenomenon.coastalFlooding, true) => 'Vagues-submersion',
        (VigilancePhenomenon.wind, false) => 'Wind',
        (VigilancePhenomenon.rainFlood, false) => 'Rain and flooding',
        (VigilancePhenomenon.thunderstorms, false) => 'Thunderstorms',
        (VigilancePhenomenon.floods, false) => 'Flooding',
        (VigilancePhenomenon.snowIce, false) => 'Snow and ice',
        (VigilancePhenomenon.heatwave, false) => 'Heatwave',
        (VigilancePhenomenon.extremeCold, false) => 'Extreme cold',
        (VigilancePhenomenon.avalanches, false) => 'Avalanches',
        (VigilancePhenomenon.coastalFlooding, false) => 'Coastal flooding',
      };
}

enum VigilancePushOutcome {
  sent,
  invalidToken,
  transientFailure,
  permanentFailure,
}

abstract interface class VigilancePushSender {
  Future<VigilancePushOutcome> send(PendingVigilanceDelivery delivery);
}

final class VigilancePushDispatchReport {
  const VigilancePushDispatchReport({
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

final class VigilancePushDispatcher {
  VigilancePushDispatcher({
    required VigilanceAlertStore store,
    required VigilancePushSender sender,
    DateTime Function()? now,
    this.maximumAttempts = 5,
    int maximumConcurrentSends = 32,
    int maximumBatches = 10,
  }) : _store = store,
       _sender = sender,
       _now = now ?? DateTime.now,
       maximumConcurrentSends = max(1, maximumConcurrentSends),
       maximumBatches = max(1, maximumBatches);

  final VigilanceAlertStore _store;
  final VigilancePushSender _sender;
  final DateTime Function() _now;
  final int maximumAttempts;
  final int maximumConcurrentSends;
  final int maximumBatches;

  Future<VigilancePushDispatchReport> flush() async {
    var pendingCount = 0;
    var sent = 0;
    var retried = 0;
    var failed = 0;
    var invalidTokens = 0;
    for (var batch = 0; batch < maximumBatches; batch += 1) {
      final pending = await _store.listPendingVigilanceDeliveries(limit: 500);
      if (pending.isEmpty) break;
      pendingCount += pending.length;
      for (
        var offset = 0;
        offset < pending.length;
        offset += maximumConcurrentSends
      ) {
        final end = min(offset + maximumConcurrentSends, pending.length);
        final results = await Future.wait(
          pending.sublist(offset, end).map(_sendOne),
        );
        for (final result in results) {
          sent += result.sent;
          retried += result.retried;
          failed += result.failed;
          invalidTokens += result.invalidTokens;
        }
      }
      if (pending.length < 500) break;
    }
    return VigilancePushDispatchReport(
      pending: pendingCount,
      sent: sent,
      retried: retried,
      failed: failed,
      invalidTokens: invalidTokens,
    );
  }

  Future<({int sent, int retried, int failed, int invalidTokens})> _sendOne(
    PendingVigilanceDelivery delivery,
  ) async {
    final outcome = await _sender.send(delivery);
    switch (outcome) {
      case VigilancePushOutcome.sent:
        await _store.markVigilanceDeliverySent(
          delivery.draft.eventId,
          _now().toUtc(),
        );
        return (sent: 1, retried: 0, failed: 0, invalidTokens: 0);
      case VigilancePushOutcome.invalidToken:
        await _store.disableDeviceToken(delivery.draft.ownerHash);
        await _store.failVigilanceDelivery(
          delivery.draft.eventId,
          'invalid_push_token',
        );
        return (sent: 0, retried: 0, failed: 0, invalidTokens: 1);
      case VigilancePushOutcome.transientFailure:
        final attempts = delivery.attempts + 1;
        if (attempts >= maximumAttempts) {
          await _store.failVigilanceDelivery(
            delivery.draft.eventId,
            'retry_limit_reached',
          );
          return (sent: 0, retried: 0, failed: 1, invalidTokens: 0);
        }
        final delayMinutes = min(60, 1 << attempts);
        await _store.retryVigilanceDelivery(
          delivery.draft.eventId,
          attempts: attempts,
          nextAttemptAt: _now().toUtc().add(Duration(minutes: delayMinutes)),
        );
        return (sent: 0, retried: 1, failed: 0, invalidTokens: 0);
      case VigilancePushOutcome.permanentFailure:
        await _store.failVigilanceDelivery(
          delivery.draft.eventId,
          'permanent_push_failure',
        );
        return (sent: 0, retried: 0, failed: 1, invalidTokens: 0);
    }
  }
}
