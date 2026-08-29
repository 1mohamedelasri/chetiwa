import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 29, 12);

  test('parses department timelines and excludes coastal subdomains', () {
    final snapshot = MeteoFranceVigilanceProvider.parse(<String, Object?>{
      'meta': <String, Object?>{
        'snapshot_id': 'snapshot-1',
        'product_datetime': now.toIso8601String(),
      },
      'product': <String, Object?>{
        'periods': <Object?>[
          <String, Object?>{
            'begin_validity_time': now.toIso8601String(),
            'end_validity_time': now
                .add(const Duration(hours: 18))
                .toIso8601String(),
            'timelaps': <String, Object?>{
              'domain_ids': <Object?>[
                <String, Object?>{
                  'domain_id': '29',
                  'phenomenon_items': <Object?>[
                    <String, Object?>{
                      'phenomenon_id': '3',
                      'phenomenon_max_color_id': 3,
                      'timelaps_items': <Object?>[
                        <String, Object?>{
                          'begin_time': now.toIso8601String(),
                          'end_time': now
                              .add(const Duration(hours: 4))
                              .toIso8601String(),
                          'color_id': 3,
                        },
                      ],
                    },
                    <String, Object?>{
                      'phenomenon_id': '4',
                      'phenomenon_max_color_id': 2,
                      'timelaps_items': <Object?>[],
                    },
                  ],
                },
                <String, Object?>{
                  'domain_id': '2910',
                  'phenomenon_items': <Object?>[
                    <String, Object?>{
                      'phenomenon_id': '9',
                      'phenomenon_max_color_id': 4,
                      'timelaps_items': <Object?>[],
                    },
                  ],
                },
              ],
            },
          },
        ],
      },
    });

    expect(snapshot.snapshotId, 'snapshot-1');
    expect(snapshot.events, hasLength(2));
    expect(snapshot.events.first.phenomenon, VigilancePhenomenon.thunderstorms);
    expect(snapshot.events.first.level, VigilanceLevel.orange);
    expect(snapshot.events.last.phenomenon, VigilancePhenomenon.floods);
    expect(snapshot.events.last.beginsAt, now);
  });

  test(
    'obtains and reuses an OAuth token without exposing credentials',
    () async {
      var tokenRequests = 0;
      var productRequests = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/token') {
          tokenRequests += 1;
          expect(request.headers['authorization'], 'Basic application-secret');
          expect(request.body, 'grant_type=client_credentials');
          return http.Response(
            jsonEncode(<String, Object?>{
              'access_token': 'temporary-token',
              'expires_in': 3600,
            }),
            200,
          );
        }
        productRequests += 1;
        expect(request.headers['authorization'], 'Bearer temporary-token');
        return http.Response(
          jsonEncode(<String, Object?>{
            'meta': <String, Object?>{
              'snapshot_id': 'oauth-product',
              'product_datetime': now.toIso8601String(),
            },
            'product': <String, Object?>{'periods': <Object?>[]},
          }),
          200,
        );
      });
      final provider = MeteoFranceVigilanceProvider(
        client: client,
        applicationId: 'application-secret',
        tokenUri: Uri.parse('https://meteofrance.test/token'),
        productUri: Uri.parse('https://meteofrance.test/vigilance'),
        now: () => now,
      );

      await provider.current();
      await provider.current();

      expect(tokenRequests, 1);
      expect(productRequests, 2);
    },
  );

  test('notifies once, reports level changes, then reports the end', () async {
    final provider = _Provider(_snapshot(now, VigilanceLevel.orange));
    final store = _Store(_active(now));
    final engine = VigilanceAlertEngine(
      store: store,
      provider: provider,
      now: () => now,
    );

    final first = await engine.run();
    expect(first.deliveriesEnqueued, 1);
    expect(store.deliveries.single.kind, VigilanceDeliveryKind.started);
    expect(store.deliveries.single.title, contains('orange'));

    final duplicate = await engine.run();
    expect(duplicate.deliveriesProposed, 0);

    provider.snapshot = _snapshot(now, VigilanceLevel.red);
    final escalation = await engine.run();
    expect(escalation.deliveriesEnqueued, 1);
    expect(store.deliveries.last.kind, VigilanceDeliveryKind.changed);
    expect(store.deliveries.last.level, VigilanceLevel.red);

    provider.snapshot = VigilanceSnapshot(
      snapshotId: 'green',
      productAt: now,
      events: const <VigilanceEvent>[],
    );
    final ended = await engine.run();
    expect(ended.deliveriesEnqueued, 1);
    expect(store.deliveries.last.kind, VigilanceDeliveryKind.ended);

    final duplicateEnd = await engine.run();
    expect(duplicateEnd.deliveriesProposed, 0);
  });

  test('yellow is ignored by the safe orange default', () async {
    final store = _Store(_active(now));
    final engine = VigilanceAlertEngine(
      store: store,
      provider: _Provider(_snapshot(now, VigilanceLevel.yellow)),
      now: () => now,
    );

    final report = await engine.run();

    expect(report.deliveriesProposed, 0);
    expect(store.deliveries, isEmpty);
  });

  test(
    'shadow mode does not acknowledge warnings before sending starts',
    () async {
      final provider = _Provider(_snapshot(now, VigilanceLevel.orange));
      final store = _Store(_active(now));
      final shadow = VigilanceAlertEngine(
        store: store,
        provider: provider,
        now: () => now,
        enqueueDeliveries: false,
      );

      expect((await shadow.run()).deliveriesProposed, 1);
      expect(store.deliveries, isEmpty);

      final live = VigilanceAlertEngine(
        store: store,
        provider: provider,
        now: () => now,
      );
      expect((await live.run()).deliveriesEnqueued, 1);
      expect(store.deliveries.single.level, VigilanceLevel.orange);
    },
  );

  test(
    'a preference change does not emit a false warning-ended push',
    () async {
      const oldSettings = VigilanceAlertSettings(
        enabled: true,
        departmentCode: '75',
        departmentName: 'Paris',
        phenomena: <VigilancePhenomenon>{VigilancePhenomenon.thunderstorms},
      );
      const newSettings = VigilanceAlertSettings(
        enabled: true,
        minimumLevel: VigilanceLevel.red,
        departmentCode: '75',
        departmentName: 'Paris',
        phenomena: <VigilancePhenomenon>{VigilancePhenomenon.thunderstorms},
      );
      final state = VigilanceAlertState(
        ownerHash: 'owner',
        alertId: 'alert',
        settingsFingerprint: vigilanceSettingsFingerprint(oldSettings),
        phenomena: <VigilancePhenomenon, VigilancePhenomenonState>{
          VigilancePhenomenon.thunderstorms: VigilancePhenomenonState(
            level: VigilanceLevel.orange,
            beginsAt: now.subtract(const Duration(hours: 1)),
            endsAt: now.add(const Duration(hours: 6)),
          ),
        },
      );
      final store = _Store(_active(now, vigilance: newSettings, state: state));
      final engine = VigilanceAlertEngine(
        store: store,
        provider: _Provider(_snapshot(now, VigilanceLevel.orange)),
        now: () => now,
      );

      expect((await engine.run()).deliveriesProposed, 0);
      expect(store.deliveries, isEmpty);
    },
  );

  test(
    'European warnings are matched against the exact user location',
    () async {
      const europeSettings = VigilanceAlertSettings(
        enabled: true,
        phenomena: <VigilancePhenomenon>{VigilancePhenomenon.rainFlood},
      );
      final snapshot = VigilanceSnapshot(
        snapshotId: 'meteoalarm-belgium',
        productAt: now,
        events: <VigilanceEvent>[
          VigilanceEvent(
            phenomenon: VigilancePhenomenon.rainFlood,
            level: VigilanceLevel.orange,
            beginsAt: now.subtract(const Duration(minutes: 10)),
            endsAt: now.add(const Duration(hours: 3)),
            polygons: const <VigilancePolygon>[
              VigilancePolygon(
                outer: <VigilancePoint>[
                  VigilancePoint(latitude: 50.7, longitude: 4.1),
                  VigilancePoint(latitude: 50.7, longitude: 4.6),
                  VigilancePoint(latitude: 51.1, longitude: 4.6),
                  VigilancePoint(latitude: 51.1, longitude: 4.1),
                ],
              ),
            ],
          ),
        ],
      );
      final store = _Store(
        _active(
          now,
          vigilance: europeSettings,
          location: const AlertLocation(
            label: 'Bruxelles',
            latitude: 50.85,
            longitude: 4.35,
            timeZone: 'Europe/Brussels',
          ),
        ),
      );
      final engine = VigilanceAlertEngine(
        store: store,
        provider: _Provider(snapshot),
        now: () => now,
        scope: VigilanceAlertScope.outsideFrance,
        source: 'meteoalarm',
        officialUrl: 'https://www.meteoalarm.org',
        sourceLabelFrench: 'MeteoAlarm',
        sourceLabelEnglish: 'MeteoAlarm',
      );

      expect((await engine.run()).deliveriesEnqueued, 1);
      expect(store.deliveries.single.source, 'meteoalarm');
      expect(store.deliveries.single.departmentName, 'Bruxelles');
    },
  );
}

VigilanceSnapshot _snapshot(DateTime now, VigilanceLevel level) =>
    VigilanceSnapshot(
      snapshotId: level.name,
      productAt: now,
      events: <VigilanceEvent>[
        VigilanceEvent(
          departmentCode: '75',
          phenomenon: VigilancePhenomenon.thunderstorms,
          level: level,
          beginsAt: now.subtract(const Duration(hours: 1)),
          endsAt: now.add(const Duration(hours: 6)),
        ),
      ],
    );

ActiveVigilanceAlert _active(
  DateTime now, {
  VigilanceAlertSettings vigilance = const VigilanceAlertSettings(
    enabled: true,
    departmentCode: '75',
    departmentName: 'Paris',
    phenomena: <VigilancePhenomenon>{VigilancePhenomenon.thunderstorms},
  ),
  VigilanceAlertState? state,
  AlertLocation location = const AlertLocation(
    label: 'Paris',
    latitude: 48.85,
    longitude: 2.35,
    timeZone: 'Europe/Paris',
  ),
}) => ActiveVigilanceAlert(
  device: DeviceRecord(
    ownerHash: 'owner',
    platform: 'android',
    locale: 'fr',
    timeZone: 'Europe/Paris',
    notificationsEnabled: true,
    pushToken: 'token',
    createdAt: now,
    updatedAt: now,
    expiresAt: now.add(const Duration(days: 1)),
  ),
  rule: AlertRuleRecord(
    id: 'alert',
    ownerHash: 'owner',
    location: location,
    leadMinutes: 15,
    minimumIntensity: 'moderate',
    quietHours: const QuietHours(enabled: false, start: '22:00', end: '07:00'),
    enabled: false,
    vigilance: vigilance,
    createdAt: now,
    updatedAt: now,
  ),
  state:
      state ?? const VigilanceAlertState(ownerHash: 'owner', alertId: 'alert'),
);

final class _Provider implements VigilanceProvider {
  _Provider(this.snapshot);

  VigilanceSnapshot snapshot;

  @override
  Future<VigilanceSnapshot> current() async => snapshot;
}

final class _Store implements VigilanceAlertStore {
  _Store(ActiveVigilanceAlert active) : _active = active;

  ActiveVigilanceAlert _active;
  final List<VigilanceDeliveryDraft> deliveries = <VigilanceDeliveryDraft>[];
  final Set<String> _eventIds = <String>{};

  @override
  Future<List<ActiveVigilanceAlert>> listActiveVigilanceAlerts() async =>
      <ActiveVigilanceAlert>[_active];

  @override
  Future<void> saveVigilanceState(VigilanceAlertState state) async {
    _active = ActiveVigilanceAlert(
      device: _active.device,
      rule: _active.rule,
      state: state,
    );
  }

  @override
  Future<bool> enqueueVigilanceDelivery(VigilanceDeliveryDraft delivery) async {
    if (!_eventIds.add(delivery.eventId)) return false;
    deliveries.add(delivery);
    return true;
  }

  @override
  Future<void> disableDeviceToken(String ownerHash) async {}

  @override
  Future<void> failVigilanceDelivery(String eventId, String reason) async {}

  @override
  Future<List<PendingVigilanceDelivery>> listPendingVigilanceDeliveries({
    int limit = 500,
  }) async => const <PendingVigilanceDelivery>[];

  @override
  Future<void> markVigilanceDeliverySent(
    String eventId,
    DateTime sentAt,
  ) async {}

  @override
  Future<void> retryVigilanceDelivery(
    String eventId, {
    required int attempts,
    required DateTime nextAttemptAt,
  }) async {}
}
