import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:test/test.dart';

void main() {
  final baseNow = DateTime.utc(2026, 8, 24, 10);

  test(
    'mutualizes one provider evaluation per stable geographic cell',
    () async {
      var now = baseNow;
      final store = _MemoryEngineStore(<ActiveRainAlert>[
        _alert(owner: 'owner-a', latitude: 48.8566, longitude: 2.3522),
        _alert(owner: 'owner-b', latitude: 48.8570, longitude: 2.3530),
      ]);
      final provider = _NowcastProvider(<RainNowcastSample>[
        RainNowcastSample(
          time: baseNow.add(const Duration(minutes: 10)),
          rateMmPerHour: 2,
        ),
      ]);
      final engine = RainAlertEngine(
        store: store,
        provider: provider,
        now: () => now,
        localTime: (utc, _) => utc,
      );

      final first = await engine.run();
      expect(first.cellsEvaluated, 1);
      expect(first.alertsEvaluated, 2);
      expect(first.deliveriesProposed, 2);
      expect(first.deliveriesEnqueued, 2);
      expect(provider.calls, 1);

      now = now.add(const Duration(minutes: 5));
      final second = await engine.run();
      expect(second.deliveriesEnqueued, 0);
      expect(store.deliveries, hasLength(2));
    },
  );

  test(
    'dry cells sleep until their forecast horizon requires a refresh',
    () async {
      var now = baseNow;
      final store = _MemoryEngineStore(<ActiveRainAlert>[
        _alert(owner: 'dry-owner'),
      ]);
      final provider = _NowcastProvider(<RainNowcastSample>[
        for (var minutes = 0; minutes <= 240; minutes += 15)
          RainNowcastSample(
            time: baseNow.add(Duration(minutes: minutes)),
            rateMmPerHour: 0,
          ),
      ]);
      final engine = RainAlertEngine(
        store: store,
        provider: provider,
        now: () => now,
        localTime: (utc, _) => utc,
      );

      final first = await engine.run();
      expect(first.cellsEvaluated, 1);
      expect(first.cellsSkipped, 23);
      expect(provider.calls, 1);
      expect(store.states, isEmpty);
      expect(store.schedules.values.single.mode, RainAlertPollingMode.dry);
      expect(
        store.schedules.values.single.nextCheckAt,
        baseNow.add(const Duration(hours: 2)),
      );

      now = now.add(const Duration(minutes: 5));
      final skipped = await engine.run();
      expect(skipped.cellsEvaluated, 0);
      expect(skipped.cellsSkipped, 0);
      expect(provider.calls, 1);

      now = baseNow.add(const Duration(hours: 2));
      final due = await engine.run();
      expect(due.cellsEvaluated, 1);
      expect(provider.calls, 2);
    },
  );

  test('rain inside the alert window keeps five-minute polling', () async {
    final store = _MemoryEngineStore(<ActiveRainAlert>[
      _alert(owner: 'wet-owner'),
    ]);
    final engine = RainAlertEngine(
      store: store,
      provider: _NowcastProvider(<RainNowcastSample>[
        RainNowcastSample(
          time: baseNow.add(const Duration(minutes: 10)),
          rateMmPerHour: 2,
        ),
      ]),
      now: () => baseNow,
      localTime: (utc, _) => utc,
    );

    await engine.run();
    final schedule = store.schedules.values.single;
    expect(schedule.mode, RainAlertPollingMode.highFrequency);
    expect(schedule.nextCheckAt, baseNow.add(const Duration(minutes: 5)));
  });

  test('applies quiet hours in the phone timezone', () async {
    final quiet = _alert(
      owner: 'quiet-owner',
      quietHours: const QuietHours(enabled: true, start: '12:00', end: '13:00'),
    );
    final store = _MemoryEngineStore(<ActiveRainAlert>[quiet]);
    final engine = RainAlertEngine(
      store: store,
      provider: _NowcastProvider(<RainNowcastSample>[
        RainNowcastSample(
          time: baseNow.add(const Duration(minutes: 10)),
          rateMmPerHour: 6,
        ),
      ]),
      now: () => baseNow,
      localTime: (utc, _) => utc.add(const Duration(hours: 2)),
    );

    final report = await engine.run();
    expect(report.deliveriesEnqueued, 0);
    expect(store.states.single.rainExpected, isTrue);
  });

  test(
    'shadow mode records decisions without creating push deliveries',
    () async {
      var now = baseNow;
      final store = _MemoryEngineStore(<ActiveRainAlert>[
        _alert(owner: 'shadow-owner'),
      ]);
      final engine = RainAlertEngine(
        store: store,
        provider: _NowcastProvider(<RainNowcastSample>[
          RainNowcastSample(
            time: baseNow.add(const Duration(minutes: 10)),
            rateMmPerHour: 2,
          ),
        ]),
        now: () => now,
        localTime: (utc, _) => utc,
        enqueueDeliveries: false,
      );

      final first = await engine.run();
      expect(first.deliveriesProposed, 1);
      expect(first.deliveriesEnqueued, 0);
      expect(store.deliveries, isEmpty);

      now = now.add(const Duration(minutes: 5));
      final second = await engine.run();
      expect(second.deliveriesProposed, 0);
    },
  );

  test('retries transient FCM errors then disables an invalid token', () async {
    var now = baseNow;
    final store = _MemoryEngineStore(<ActiveRainAlert>[
      _alert(owner: 'owner-a'),
    ]);
    await store.enqueueDelivery(_delivery(baseNow));
    final sender = _PushSender(<PushSendOutcome>[
      PushSendOutcome.transientFailure,
      PushSendOutcome.invalidToken,
    ]);
    final dispatcher = RainAlertPushDispatcher(
      store: store,
      sender: sender,
      now: () => now,
    );

    final first = await dispatcher.flush();
    expect(first.retried, 1);
    expect(store.deliveries.single.attempts, 1);

    now = now.add(const Duration(seconds: 31));
    final second = await dispatcher.flush();
    expect(second.invalidTokens, 1);
    expect(store.disabledOwners, contains('owner-a'));
    expect(store.deliveries, isEmpty);
  });
}

ActiveRainAlert _alert({
  required String owner,
  double latitude = 48.8566,
  double longitude = 2.3522,
  QuietHours quietHours = const QuietHours(
    enabled: false,
    start: '22:00',
    end: '07:00',
  ),
}) {
  final createdAt = DateTime.utc(2026, 8, 1);
  return ActiveRainAlert(
    device: DeviceRecord(
      ownerHash: owner,
      platform: 'android',
      locale: 'fr',
      timeZone: 'Europe/Paris',
      notificationsEnabled: true,
      pushToken: 'token-$owner',
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: createdAt.add(const Duration(days: 180)),
    ),
    rule: AlertRuleRecord(
      id: 'main',
      ownerHash: owner,
      location: AlertLocation(
        label: 'Paris, France',
        latitude: latitude,
        longitude: longitude,
        timeZone: 'Europe/Paris',
      ),
      leadMinutes: 15,
      minimumIntensity: 'moderate',
      quietHours: quietHours,
      enabled: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    state: RainAlertState(ownerHash: owner, alertId: 'main'),
  );
}

AlertDeliveryDraft _delivery(DateTime now) => AlertDeliveryDraft(
  eventId: 'event-1',
  ownerHash: 'owner-a',
  alertId: 'main',
  cellKey: 'cell-1',
  location: const AlertLocation(
    label: 'Paris, France',
    latitude: 48.8566,
    longitude: 2.3522,
    timeZone: 'Europe/Paris',
  ),
  intensity: AlertRainIntensity.moderate,
  expectedAt: now.add(const Duration(minutes: 10)),
  title: 'Pluie bientôt',
  body: 'Pluie modérée prévue à Paris',
  createdAt: now,
  expiresAt: now.add(const Duration(minutes: 30)),
);

final class _NowcastProvider implements RainAlertNowcastProvider {
  _NowcastProvider(this.samples);

  final List<RainNowcastSample> samples;
  int calls = 0;

  @override
  Future<List<RainNowcastSample>> nowcast(RainAlertCell cell) async {
    calls += 1;
    return samples;
  }
}

final class _PushSender implements RainAlertPushSender {
  _PushSender(this.outcomes);

  final List<PushSendOutcome> outcomes;
  int calls = 0;

  @override
  Future<PushSendOutcome> send(PendingAlertDelivery delivery) async =>
      outcomes[calls++];
}

final class _MemoryEngineStore implements RainAlertEngineStore {
  _MemoryEngineStore(this.alerts) {
    for (final alert in alerts) {
      final cell = RainAlertCell.fromLocation(alert.rule.location);
      schedules[cell.key] = RainAlertCellSchedule(
        cellKey: cell.key,
        latitude: cell.latitude,
        longitude: cell.longitude,
        nextCheckAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        lastCheckedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        mode: RainAlertPollingMode.retry,
      );
    }
  }

  final List<ActiveRainAlert> alerts;
  final Map<String, RainAlertState> _states = <String, RainAlertState>{};
  final Map<String, RainAlertCellSchedule> schedules =
      <String, RainAlertCellSchedule>{};
  final List<PendingAlertDelivery> deliveries = <PendingAlertDelivery>[];
  final Set<String> disabledOwners = <String>{};
  String? _lease;

  Iterable<RainAlertState> get states => _states.values;

  @override
  Future<bool> acquireLease({
    required String runId,
    required DateTime now,
    required DateTime expiresAt,
  }) async {
    if (_lease != null) return false;
    _lease = runId;
    return true;
  }

  @override
  Future<void> releaseLease(String runId) async {
    if (_lease == runId) _lease = null;
  }

  @override
  Future<List<ActiveRainAlert>> listActiveAlerts() async => alerts
      .map(
        (alert) => ActiveRainAlert(
          device: alert.device,
          rule: alert.rule,
          state:
              _states['${alert.device.ownerHash}:${alert.rule.id}'] ??
              alert.state,
        ),
      )
      .toList(growable: false);

  @override
  Future<List<RainAlertCellSchedule>> listDueCellSchedules({
    required DateTime now,
    int limit = 500,
  }) async => schedules.values
      .where((schedule) => !schedule.nextCheckAt.isAfter(now))
      .take(limit)
      .toList(growable: false);

  @override
  Future<List<ActiveRainAlert>> listActiveAlertsForCell(String cellKey) async =>
      (await listActiveAlerts())
          .where(
            (alert) =>
                RainAlertCell.fromLocation(alert.rule.location).key == cellKey,
          )
          .toList(growable: false);

  @override
  Future<void> saveCellSchedule(RainAlertCellSchedule schedule) async {
    schedules[schedule.cellKey] = schedule;
  }

  @override
  Future<void> deleteCellSchedule(String cellKey) async {
    schedules.remove(cellKey);
  }

  @override
  Future<void> saveState(RainAlertState state) async {
    _states['${state.ownerHash}:${state.alertId}'] = state;
  }

  @override
  Future<bool> enqueueDelivery(AlertDeliveryDraft delivery) async {
    if (deliveries.any((item) => item.draft.eventId == delivery.eventId)) {
      return false;
    }
    final alert = alerts.firstWhere(
      (item) => item.device.ownerHash == delivery.ownerHash,
    );
    deliveries.add(
      PendingAlertDelivery(
        draft: delivery,
        pushToken: alert.device.pushToken!,
        platform: alert.device.platform,
        attempts: 0,
        nextAttemptAt: delivery.createdAt,
      ),
    );
    return true;
  }

  @override
  Future<List<PendingAlertDelivery>> listPendingDeliveries({
    int limit = 500,
  }) async => deliveries.take(limit).toList(growable: false);

  @override
  Future<void> markDeliverySent(String eventId, DateTime sentAt) async {
    deliveries.removeWhere((item) => item.draft.eventId == eventId);
  }

  @override
  Future<void> retryDelivery(
    String eventId, {
    required int attempts,
    required DateTime nextAttemptAt,
  }) async {
    final index = deliveries.indexWhere(
      (item) => item.draft.eventId == eventId,
    );
    final existing = deliveries[index];
    deliveries[index] = PendingAlertDelivery(
      draft: existing.draft,
      pushToken: existing.pushToken,
      platform: existing.platform,
      attempts: attempts,
      nextAttemptAt: nextAttemptAt,
    );
  }

  @override
  Future<void> failDelivery(String eventId, String reason) async {
    deliveries.removeWhere((item) => item.draft.eventId == eventId);
  }

  @override
  Future<void> disableDeviceToken(String ownerHash) async {
    disabledOwners.add(ownerHash);
  }
}
