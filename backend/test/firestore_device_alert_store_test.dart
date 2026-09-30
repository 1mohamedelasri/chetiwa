import 'dart:async';
import 'dart:convert';

import 'package:chetiwa_backend/chetiwa_backend.dart';
import 'package:chetiwa_backend/src/api_exception.dart';
import 'package:googleapis/firestore/v1.dart' as firestore;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final instant = DateTime.utc(2026, 8, 24, 18, 30);
  const owner =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  FirestoreDeviceAlertStore testStore(
    _FakeFirestore fake, {
    String Function()? idGenerator,
    Future<http.Response> Function(http.Request)? handler,
  }) => FirestoreDeviceAlertStore(
    api: firestore.FirestoreApi(
      MockClient(handler ?? fake.handle),
      rootUrl: 'https://firestore.test/',
    ),
    projectId: 'chetiwa-test',
    now: () => instant,
    idGenerator: idGenerator,
  );

  const registration = DeviceRegistration(
    platform: 'ios',
    locale: 'fr',
    timeZone: 'Europe/Paris',
    notificationsEnabled: true,
    pushToken: 'private-token',
  );

  test(
    'concurrent store instances cannot exceed the five-alert limit',
    () async {
      final fake = _FakeFirestore();
      var id = 0;
      final gate = Completer<void>();
      var counted = 0;
      Future<http.Response> simultaneousCount(http.Request request) async {
        final response = await fake.handle(request);
        if (request.method == 'GET' &&
            request.url.path.endsWith('/alerts') &&
            !gate.isCompleted) {
          counted++;
          if (counted == 10) gate.complete();
          await gate.future;
        }
        return response;
      }

      final stores = List.generate(
        10,
        (_) => testStore(
          fake,
          idGenerator: () => (++id).toRadixString(16).padLeft(32, '0'),
          handler: simultaneousCount,
        ),
      );
      await stores.first.upsertDevice(owner, registration);
      final results = await Future.wait(
        stores.map((store) async {
          try {
            return await store.createAlert(owner, _draft());
          } on ApiException catch (error) {
            return error;
          }
        }),
      );
      expect(results.whereType<AlertRuleRecord>(), hasLength(5));
      expect(
        results.whereType<ApiException>().map((error) => error.code),
        everyElement('alert_limit_reached'),
      );
      expect(results.whereType<ApiException>(), hasLength(5));
      expect(fake.preconditionConflicts, greaterThan(0));
      expect(await stores.first.listAlerts(owner), hasLength(5));
      final device = fake.documents.entries
          .singleWhere((entry) => entry.key.endsWith('/devices/$owner'))
          .value;
      final fields = device['fields'] as Map;
      expect(fields['alertQuotaRevision'], {'integerValue': '5'});
      expect(fields['pushToken'], {'stringValue': 'private-token'});
    },
  );

  test(
    'registration during create is preserved when the parent CAS retries',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake);
      final other = testStore(fake);
      await store.upsertDevice(owner, registration);
      fake.beforeCommit = (_) async {
        fake.beforeCommit = null;
        await other.upsertDevice(
          owner,
          const DeviceRegistration(
            platform: 'ios',
            locale: 'en',
            timeZone: 'Europe/London',
            notificationsEnabled: true,
            pushToken: 'new-token',
          ),
        );
      };

      await store.createAlert(owner, _draft());

      expect(fake.preconditionConflicts, 1);
      expect(await store.listAlerts(owner), hasLength(1));
      final fields =
          fake.documents.entries
                  .singleWhere((entry) => entry.key.endsWith('/devices/$owner'))
                  .value['fields']
              as Map;
      expect(fields['locale'], {'stringValue': 'en'});
      expect(fields['pushToken'], {'stringValue': 'new-token'});
      expect(fields['alertQuotaRevision'], {'integerValue': '1'});
    },
  );

  test('device deletion before create commit leaves no orphan alert', () async {
    final fake = _FakeFirestore();
    final store = testStore(fake);
    await store.upsertDevice(owner, registration);
    fake.beforeCommit = (_) async {
      fake.beforeCommit = null;
      await testStore(fake).deleteDevice(owner);
    };
    await expectLater(
      store.createAlert(owner, _draft()),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'device_not_registered',
        ),
      ),
    );
    expect(fake.documents, isEmpty);
    expect(fake.preconditionConflicts, 1);
  });

  test('missing parent version fails closed before writing an alert', () async {
    final fake = _FakeFirestore();
    await testStore(fake).upsertDevice(owner, registration);
    final store = testStore(
      fake,
      handler: (request) async {
        final response = await fake.handle(request);
        if (request.method != 'GET' ||
            !request.url.path.endsWith('/devices/$owner')) {
          return response;
        }
        final document = jsonDecode(response.body) as Map<String, dynamic>;
        document.remove('updateTime');
        return http.Response(
          jsonEncode(document),
          200,
          headers: {'content-type': 'application/json'},
        );
      },
    );
    await expectLater(
      store.createAlert(owner, _draft()),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'persistent_store_invalid_data',
        ),
      ),
    );
    expect(fake.documents, hasLength(1));
  });

  test(
    'deleting and reusing an alert id still changes parent revision',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake, idGenerator: () => 'fixed-alert-id');
      await store.upsertDevice(owner, registration);
      final first = await store.createAlert(owner, _draft());
      final deviceName = fake.documents.keys.singleWhere(
        (name) => name.endsWith('/devices/$owner'),
      );
      final firstVersion = fake.documents[deviceName]!['updateTime'];
      await store.deleteAlert(owner, first.id);
      await store.createAlert(owner, _draft());

      expect(fake.documents[deviceName]!['updateTime'], isNot(firstVersion));
      expect(
        (fake.documents[deviceName]!['fields'] as Map)['alertQuotaRevision'],
        {'integerValue': '2'},
      );
      expect(await store.listAlerts(owner), hasLength(1));
    },
  );

  test(
    'failed alert-id precondition never partially bumps the parent',
    () async {
      final fake = _FakeFirestore();
      var id = 0;
      final store = testStore(
        fake,
        idGenerator: () => ++id <= 2 ? 'first' : 'second',
      );
      await store.upsertDevice(owner, registration);
      await store.createAlert(owner, _draft());
      await store.createAlert(owner, _draft());

      expect(fake.preconditionConflicts, 1);
      expect(await store.listAlerts(owner), hasLength(2));
      final fields =
          fake.documents.entries
                  .singleWhere((entry) => entry.key.endsWith('/devices/$owner'))
                  .value['fields']
              as Map;
      expect(fields['alertQuotaRevision'], {'integerValue': '2'});
    },
  );

  AlertDeliveryDraft rainDelivery(AlertRuleRecord rule) => AlertDeliveryDraft(
    eventId: 'rain-event',
    ownerHash: owner,
    alertId: rule.id,
    cellKey: 'cell',
    location: rule.location,
    intensity: AlertRainIntensity.moderate,
    expectedAt: instant,
    title: 'Rain',
    body: 'Rain approaching',
    createdAt: instant,
    expiresAt: instant.add(const Duration(minutes: 30)),
  );
  VigilanceDeliveryDraft vigilanceDelivery(AlertRuleRecord rule) =>
      VigilanceDeliveryDraft(
        eventId: 'vigilance-event',
        ownerHash: owner,
        alertId: rule.id,
        departmentCode: '75',
        departmentName: 'Paris',
        phenomenon: VigilancePhenomenon.rainFlood,
        kind: VigilanceDeliveryKind.started,
        title: 'Warning',
        body: 'Official warning',
        createdAt: instant,
        expiresAt: instant.add(const Duration(hours: 1)),
        settingsFingerprint: 'settings',
      );

  test(
    'erasure marks the device before listing and rejects every new writer',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake);
      await store.upsertDevice(owner, registration);
      final rule = await store.createAlert(owner, _draft());
      await store.enqueueDelivery(rainDelivery(rule));
      final entered = Completer<void>();
      final resume = Completer<void>();
      fake.beforeRequest = (request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/alerts')) {
          fake.beforeRequest = null;
          entered.complete();
          await resume.future;
        }
      };
      final deleting = store.deleteDevice(owner);
      await entered.future;
      final device = fake.documents.entries
          .singleWhere((entry) => entry.key.endsWith('/devices/$owner'))
          .value;
      final fields = device['fields'] as Map;
      expect(fields['deleting'], {'booleanValue': true});
      expect(fields.containsKey('pushToken'), isFalse);
      expect(fields.containsKey('expiresAt'), isFalse);
      final blocked = throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'device_deletion_in_progress',
        ),
      );
      await expectLater(store.upsertDevice(owner, registration), blocked);
      await expectLater(store.createAlert(owner, _draft()), blocked);
      await expectLater(
        store.updateAlert(
          owner,
          rule.id,
          const AlertRuleChanges(enabled: false),
        ),
        blocked,
      );
      await store.disableDeviceToken(owner);
      await store.saveState(RainAlertState(ownerHash: owner, alertId: rule.id));
      await store.saveVigilanceState(
        VigilanceAlertState(ownerHash: owner, alertId: rule.id),
      );
      expect(await store.enqueueDelivery(rainDelivery(rule)), isFalse);
      expect(
        await store.enqueueVigilanceDelivery(vigilanceDelivery(rule)),
        isFalse,
      );
      expect(await store.listActiveAlerts(), isEmpty);
      expect(await store.listPendingDeliveries(), isEmpty);
      resume.complete();
      expect(await deleting, isTrue);
      expect(fake.documents, isEmpty);
      await store.upsertDevice(owner, registration);
      expect(await store.listAlerts(owner), isEmpty);
    },
  );

  test(
    'a registration read before erasure cannot recreate its parent afterward',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake);
      await store.upsertDevice(owner, registration);
      final entered = Completer<void>();
      final resume = Completer<void>();
      fake.beforeRequest = (request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('documents:commit') &&
            request.body.contains('platform')) {
          fake.beforeRequest = null;
          entered.complete();
          await resume.future;
        }
      };
      final staleRegistration = store.upsertDevice(owner, registration);
      await entered.future;
      expect(await testStore(fake).deleteDevice(owner), isTrue);
      final failure = expectLater(
        staleRegistration,
        throwsA(isA<ApiException>()),
      );
      resume.complete();
      await failure;
      expect(fake.documents, isEmpty);
    },
  );

  for (final operation in [
    'rain-state',
    'vigilance-state',
    'rain-outbox',
    'vigilance-outbox',
    'alert-update',
  ]) {
    test(
      '$operation captured before erasure cannot write after deletion',
      () async {
        final fake = _FakeFirestore();
        final store = testStore(fake);
        await store.upsertDevice(owner, registration);
        final rule = await store.createAlert(owner, _draft());
        fake.beforeCommit = (_) async {
          fake.beforeCommit = null;
          await testStore(fake).deleteDevice(owner);
        };
        switch (operation) {
          case 'rain-state':
            await store.saveState(
              RainAlertState(ownerHash: owner, alertId: rule.id),
            );
          case 'vigilance-state':
            await store.saveVigilanceState(
              VigilanceAlertState(ownerHash: owner, alertId: rule.id),
            );
          case 'rain-outbox':
            expect(await store.enqueueDelivery(rainDelivery(rule)), isFalse);
          case 'vigilance-outbox':
            expect(
              await store.enqueueVigilanceDelivery(vigilanceDelivery(rule)),
              isFalse,
            );
          case 'alert-update':
            await expectLater(
              store.updateAlert(
                owner,
                rule.id,
                const AlertRuleChanges(enabled: false),
              ),
              throwsA(isA<ApiException>()),
            );
        }
        expect(fake.documents, isEmpty);
      },
    );
  }

  test(
    'partial batch failure keeps a resumable marker and removes legacy orphans',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake);
      await store.upsertDevice(owner, registration);
      await store.createAlert(owner, _draft());
      const documents = 'projects/chetiwa-test/databases/(default)/documents';
      for (var index = 0; index < 510; index++) {
        final collection = index.isEven ? 'alertStates' : 'vigilanceStates';
        fake._writeDocument('$documents/$collection/legacy-$index', {
          'fields': {
            'ownerHash': {'stringValue': owner},
          },
        });
      }
      var batches = 0;
      fake.beforeCommit = (writes) async {
        if (writes.any((write) => write.containsKey('delete')) &&
            ++batches == 2) {
          throw firestore.DetailedApiRequestError(
            503,
            'injected batch failure',
          );
        }
      };
      await expectLater(
        store.deleteDevice(owner),
        throwsA(isA<ApiException>()),
      );
      final remaining = fake.documents.values
          .where(
            (document) => (document['fields'] as Map?)?['ownerHash'] != null,
          )
          .length;
      expect(remaining, greaterThan(0));
      expect(remaining, lessThan(510));
      final marker =
          fake.documents['$documents/devices/$owner']!['fields'] as Map;
      expect(marker['deleting'], {'booleanValue': true});
      expect(marker.containsKey('pushToken'), isFalse);
      await expectLater(
        store.upsertDevice(owner, registration),
        throwsA(isA<ApiException>()),
      );
      fake.beforeCommit = null;
      expect(await store.deleteDevice(owner), isTrue);
      expect(
        fake.documents.keys.where(
          (name) => !name.contains('/alertCellSchedules/'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'an overlapping old erasure cannot delete a new registration or reused alert',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake, idGenerator: () => 'same-alert');
      await store.upsertDevice(owner, registration);
      await store.createAlert(owner, _draft());
      final entered = Completer<void>();
      final resume = Completer<void>();
      fake.beforeCommit = (writes) async {
        if (writes.any((write) => write.containsKey('delete'))) {
          fake.beforeCommit = null;
          entered.complete();
          await resume.future;
        }
      };
      final staleDeletion = store.deleteDevice(owner);
      await entered.future;
      expect(await testStore(fake).deleteDevice(owner), isTrue);
      await store.upsertDevice(owner, registration);
      await store.createAlert(owner, _draft());
      resume.complete();
      expect(await staleDeletion, isTrue);
      expect(await store.listAlerts(owner), hasLength(1));
      expect(
        fake.documents.values.any(
          (document) => (document['fields'] as Map?)?['deleting'] != null,
        ),
        isFalse,
      );
    },
  );

  test(
    'an old worker skips missing alerts after the device registers again',
    () async {
      final fake = _FakeFirestore();
      final store = testStore(fake);
      await store.upsertDevice(owner, registration);
      final oldRule = await store.createAlert(owner, _draft());
      await store.deleteDevice(owner);
      await store.upsertDevice(owner, registration);
      await store.saveState(
        RainAlertState(ownerHash: owner, alertId: oldRule.id),
      );
      expect(await store.enqueueDelivery(rainDelivery(oldRule)), isFalse);
      expect(fake.documents, hasLength(1));
    },
  );

  RainAlertCellSchedule deferred(RainAlertCellSchedule current) =>
      RainAlertCellSchedule(
        cellKey: current.cellKey,
        latitude: current.latitude,
        longitude: current.longitude,
        lastCheckedAt: instant,
        nextCheckAt: instant.add(const Duration(hours: 1)),
        mode: RainAlertPollingMode.dry,
      );

  test(
    'same-time new subscriptions change the version and reject stale worker save/delete',
    () async {
      final fake = _FakeFirestore();
      final worker = testStore(fake);
      final api = testStore(fake);
      await api.upsertDevice(owner, registration);
      await api.createAlert(owner, _draft());
      final old = (await worker.listDueCellSchedules(now: instant)).single;
      await api.createAlert(owner, _draft());
      final fresh = (await worker.listDueCellSchedules(now: instant)).single;
      expect(fresh.version, isNot(old.version));
      await worker.saveCellSchedule(
        deferred(old),
        expectedVersion: old.version,
      );
      await worker.deleteCellSchedule(
        old.cellKey,
        expectedVersion: old.version,
      );
      await worker.saveCellSchedule(
        deferred(old),
      ); // Missing version is create-only.
      expect(
        (await worker.listDueCellSchedules(now: instant)).single.version,
        fresh.version,
      );

      await worker.saveCellSchedule(
        deferred(fresh),
        expectedVersion: fresh.version,
      );
      expect(await worker.listDueCellSchedules(now: instant), isEmpty);
      final fields =
          fake.documents.entries
                  .singleWhere(
                    (entry) => entry.key.contains('/alertCellSchedules/'),
                  )
                  .value['fields']
              as Map;
      expect(fields['wakeupRevision'], {'integerValue': '2'});
    },
  );

  test(
    'API empty-cell cleanup cannot delete a subscription added after its check',
    () async {
      final fake = _FakeFirestore();
      final cleanup = testStore(fake);
      final api = testStore(fake);
      await api.upsertDevice(owner, registration);
      final rule = await api.createAlert(owner, _draft());
      final schedule = (await api.listDueCellSchedules(now: instant)).single;
      await api.deleteAlert(owner, rule.id);
      fake.beforeRequest = (request) async {
        if (request.method == 'DELETE' &&
            request.url.path.contains('/alertCellSchedules/')) {
          fake.beforeRequest = null;
          await api.createAlert(owner, _draft());
        }
      };
      await cleanup.deleteCellSchedule(schedule.cellKey);
      expect(await api.listAlerts(owner), hasLength(1));
      final current = (await api.listDueCellSchedules(now: instant)).single;
      expect(current.version, isNot(schedule.version));
    },
  );

  test(
    'reactivating a device atomically wakes existing rules before stale cleanup',
    () async {
      final fake = _FakeFirestore();
      final worker = testStore(fake);
      final api = testStore(fake);
      await api.upsertDevice(owner, registration);
      await api.createAlert(owner, _draft());
      await api.disableDeviceToken(owner);
      final old = (await worker.listDueCellSchedules(now: instant)).single;
      await api.upsertDevice(owner, registration);
      final wakeup = (await worker.listDueCellSchedules(now: instant)).single;
      expect(wakeup.version, isNot(old.version));
      await worker.deleteCellSchedule(
        old.cellKey,
        expectedVersion: old.version,
      );
      await worker.saveCellSchedule(
        deferred(old),
        expectedVersion: old.version,
      );
      await api.upsertDevice(
        owner,
        registration,
      ); // Routine sync must not reset polling.
      expect(
        (await worker.listDueCellSchedules(now: instant)).single.version,
        wakeup.version,
      );
    },
  );

  test(
    'alert creation and its wakeup either commit together or neither exists',
    () async {
      final fake = _FakeFirestore();
      final api = testStore(fake);
      await api.upsertDevice(owner, registration);
      fake.beforeCommit = (writes) async {
        expect(
          writes.any(
            (write) => ((write['update'] as Map?)?['name'] as String? ?? '')
                .contains('/alerts/'),
          ),
          isTrue,
        );
        expect(
          writes.any(
            (write) => ((write['update'] as Map?)?['name'] as String? ?? '')
                .contains('/alertCellSchedules/'),
          ),
          isTrue,
        );
        throw firestore.DetailedApiRequestError(
          503,
          'injected atomic wakeup failure',
        );
      };
      await expectLater(
        api.createAlert(owner, _draft()),
        throwsA(isA<ApiException>()),
      );
      expect(fake.documents, hasLength(1));
      expect(await api.listAlerts(owner), isEmpty);
    },
  );

  test(
    'same-cell alert changes wake atomically and invalidate old polling results',
    () async {
      final fake = _FakeFirestore();
      final api = testStore(fake);
      await api.upsertDevice(owner, registration);
      final rule = await api.createAlert(owner, _draft());
      final old = (await api.listDueCellSchedules(now: instant)).single;
      await api.updateAlert(
        owner,
        rule.id,
        const AlertRuleChanges(leadMinutes: 30),
      );
      final wakeup = (await api.listDueCellSchedules(now: instant)).single;
      expect(wakeup.version, isNot(old.version));
      await testStore(
        fake,
      ).saveCellSchedule(deferred(old), expectedVersion: old.version);
      expect(
        (await api.listDueCellSchedules(now: instant)).single.version,
        wakeup.version,
      );
    },
  );

  test('Firestore schedules missing server version fail closed', () async {
    final fake = _FakeFirestore();
    final api = testStore(fake);
    await api.upsertDevice(owner, registration);
    await api.createAlert(owner, _draft());
    final store = testStore(
      fake,
      handler: (request) async {
        final response = await fake.handle(request);
        if (request.url.path.endsWith('documents:runQuery') &&
            request.body.contains('alertCellSchedules')) {
          final body = (jsonDecode(response.body) as List)
              .cast<Map<String, dynamic>>();
          for (final item in body) {
            (item['document'] as Map).remove('updateTime');
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return response;
      },
    );
    await expectLater(
      store.listDueCellSchedules(now: instant),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'persistent_store_invalid_data',
        ),
      ),
    );
  });

  test('persists device and alert records across store instances', () async {
    final fake = _FakeFirestore();
    var id = 0;
    FirestoreDeviceAlertStore store() => FirestoreDeviceAlertStore(
      api: firestore.FirestoreApi(
        MockClient(fake.handle),
        rootUrl: 'https://firestore.test/',
      ),
      projectId: 'chetiwa-test',
      now: () => instant,
      idGenerator: () => (++id).toRadixString(16).padLeft(32, '0'),
    );

    final first = store();
    final device = await first.upsertDevice(
      owner,
      const DeviceRegistration(
        platform: 'android',
        locale: 'fr',
        timeZone: 'Europe/Paris',
        notificationsEnabled: true,
        pushToken: 'private-token',
        appVersion: '1.0.0+1',
      ),
    );
    await first.createAlert(owner, _draft());

    final restarted = store();
    final alerts = await restarted.listAlerts(owner);

    expect(device.pushToken, 'private-token');
    expect(device.expiresAt, instant.add(const Duration(days: 180)));
    expect(alerts, hasLength(1));
    expect(alerts.single.location.label, 'Paris, France');
    expect(alerts.single.minimumIntensity, 'moderate');
  });

  test('device deletion atomically removes its alert subcollection', () async {
    final fake = _FakeFirestore();
    final store = FirestoreDeviceAlertStore(
      api: firestore.FirestoreApi(
        MockClient(fake.handle),
        rootUrl: 'https://firestore.test/',
      ),
      projectId: 'chetiwa-test',
      now: () => instant,
      idGenerator: () => '1'.padLeft(32, '0'),
    );
    await store.upsertDevice(
      owner,
      const DeviceRegistration(
        platform: 'ios',
        locale: 'fr',
        timeZone: 'Europe/Paris',
        notificationsEnabled: true,
        pushToken: 'private-token',
      ),
    );
    await store.createAlert(owner, _draft());

    expect(await store.deleteDevice(owner), isTrue);
    await expectLater(
      store.listAlerts(owner),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'device_not_registered',
        ),
      ),
    );
    expect(fake.documents, isEmpty);
  });

  test('persists engine state and a deduplicated delivery outbox', () async {
    final fake = _FakeFirestore();
    final store = FirestoreDeviceAlertStore(
      api: firestore.FirestoreApi(
        MockClient(fake.handle),
        rootUrl: 'https://firestore.test/',
      ),
      projectId: 'chetiwa-test',
      now: () => instant,
      idGenerator: () => '1'.padLeft(32, '0'),
    );
    await store.upsertDevice(
      owner,
      const DeviceRegistration(
        platform: 'android',
        locale: 'fr',
        timeZone: 'Europe/Paris',
        notificationsEnabled: true,
        pushToken: 'private-token',
      ),
    );
    final rule = await store.createAlert(owner, _draft());

    final active = await store.listActiveAlerts();
    expect(active, hasLength(1));
    expect(active.single.state.rainExpected, isFalse);
    final dueCells = await store.listDueCellSchedules(now: instant);
    expect(dueCells, hasLength(1));
    final activeInCell = await store.listActiveAlertsForCell(
      dueCells.single.cellKey,
    );
    expect(activeInCell, hasLength(1));
    await store.saveState(
      RainAlertState(
        ownerHash: owner,
        alertId: rule.id,
        rainExpected: true,
        lastIntensity: AlertRainIntensity.moderate,
        updatedAt: instant,
      ),
    );
    final delivery = AlertDeliveryDraft(
      eventId: 'event-1',
      ownerHash: owner,
      alertId: rule.id,
      cellKey: 'cell-1',
      location: rule.location,
      intensity: AlertRainIntensity.moderate,
      expectedAt: instant.add(const Duration(minutes: 10)),
      title: 'Pluie bientôt',
      body: 'Pluie modérée prévue à Paris',
      createdAt: instant,
      expiresAt: instant.add(const Duration(minutes: 30)),
    );
    expect(await store.enqueueDelivery(delivery), isTrue);
    expect(await store.enqueueDelivery(delivery), isFalse);

    final pending = await store.listPendingDeliveries();
    expect(pending, hasLength(1));
    expect(pending.single.pushToken, 'private-token');
    expect(pending.single.draft.eventId, 'event-1');
  });

  test('persists adaptive polling state without device coordinates', () async {
    final fake = _FakeFirestore();
    final store = FirestoreDeviceAlertStore(
      api: firestore.FirestoreApi(
        MockClient(fake.handle),
        rootUrl: 'https://firestore.test/',
      ),
      projectId: 'chetiwa-test',
      now: () => instant,
    );
    const cellKey = '0.050:2777:3647';
    final schedule = RainAlertCellSchedule(
      cellKey: cellKey,
      latitude: 48.875,
      longitude: 2.375,
      lastCheckedAt: instant,
      nextCheckAt: instant.add(const Duration(hours: 2)),
      mode: RainAlertPollingMode.dry,
    );

    await store.saveCellSchedule(schedule);
    final restored = await store.listDueCellSchedules(
      now: instant.add(const Duration(hours: 3)),
    );

    expect(restored.single.mode, RainAlertPollingMode.dry);
    expect(restored.single.nextCheckAt, schedule.nextCheckAt);
    final encoded = jsonEncode(fake.documents.values.toList());
    expect(encoded, isNot(contains('private-token')));
    expect(encoded, isNot(contains('48.8566')));
  });

  test(
    'persists safe run metrics and applies the hard budget cutoff',
    () async {
      final fake = _FakeFirestore();
      final store = FirestoreDeviceAlertStore(
        api: firestore.FirestoreApi(
          MockClient(fake.handle),
          rootUrl: 'https://firestore.test/',
        ),
        projectId: 'chetiwa-test',
        now: () => instant,
      );
      const fallback = RainAlertRuntimeControl(
        engineEnabled: true,
        sendEnabled: true,
        observedCostCents: 0,
        softBudgetCents: 2500,
        hardBudgetCents: 5000,
      );

      await store.recordRunMetric(
        RainAlertRunMetric(
          runId: 'rain-1',
          startedAt: instant,
          durationMilliseconds: 125,
          mode: 'shadow',
          status: 'completed',
          activeAlerts: 2,
          cellsEvaluated: 1,
          providerFailures: 0,
          alertsEvaluated: 2,
          deliveriesProposed: 1,
          deliveriesEnqueued: 0,
          pushPending: 0,
          pushSent: 0,
          pushRetried: 0,
          pushFailed: 0,
          invalidTokens: 0,
        ),
      );
      final metric = fake.documents.entries.singleWhere(
        (entry) => entry.key.endsWith('/alertRunMetrics/rain-1'),
      );
      final serialized = jsonEncode(metric.value);
      expect(serialized, isNot(contains('pushToken')));
      expect(serialized, isNot(contains('latitude')));
      expect(serialized, isNot(contains('longitude')));

      await store.updateObservedCost(
        observedCostCents: 100,
        costIntervalStart: DateTime.utc(2026, 8),
        fallback: const RainAlertRuntimeControl(
          engineEnabled: false,
          sendEnabled: false,
          observedCostCents: 0,
          softBudgetCents: 2500,
          hardBudgetCents: 5000,
        ),
      );
      final enabledByNewDeployment = await store.loadRuntimeControl(fallback);
      expect(enabledByNewDeployment.engineEnabled, isTrue);
      expect(enabledByNewDeployment.sendEnabled, isTrue);

      final soft = await store.updateObservedCost(
        observedCostCents: 2500,
        costIntervalStart: DateTime.utc(2026, 8),
        fallback: fallback,
      );
      expect(soft.softBudgetExceeded, isTrue);
      expect(soft.maySend, isTrue);

      final hard = await store.updateObservedCost(
        observedCostCents: 5100,
        costIntervalStart: DateTime.utc(2026, 8),
        fallback: fallback,
      );
      expect(hard.hardBudgetExceeded, isTrue);
      expect(hard.engineEnabled, isFalse);
      expect(hard.sendEnabled, isFalse);

      final stale = await store.updateObservedCost(
        observedCostCents: 10,
        costIntervalStart: DateTime.utc(2026, 7),
        fallback: fallback,
      );
      expect(stale.observedCostCents, 5100);
    },
  );
}

AlertRuleDraft _draft() => const AlertRuleDraft(
  location: AlertLocation(
    label: 'Paris, France',
    latitude: 48.8566,
    longitude: 2.3522,
    timeZone: 'Europe/Paris',
  ),
  leadMinutes: 15,
  minimumIntensity: 'moderate',
  quietHours: QuietHours(enabled: true, start: '22:00', end: '07:00'),
  enabled: true,
);

final class _FakeFirestore {
  final Map<String, Map<String, Object?>> documents =
      <String, Map<String, Object?>>{};
  Future<void> Function(List<Map<String, dynamic>>)? beforeCommit;
  Future<void> Function(http.Request)? beforeRequest;
  var preconditionConflicts = 0;
  var _version = 0;

  void _writeDocument(
    String name,
    Map<String, Object?> document, {
    List<String>? mask,
    List<Map<String, dynamic>> transforms = const [],
  }) {
    final previous = documents[name];
    final fields = Map<String, Object?>.from(document['fields'] as Map? ?? {});
    final nextFields = mask == null
        ? fields
        : <String, Object?>{
            ...?previous?['fields'] as Map<String, Object?>?,
            for (final field in mask)
              if (fields.containsKey(field)) field: fields[field],
          };
    if (mask != null) {
      for (final field in mask) {
        if (!fields.containsKey(field)) nextFields.remove(field);
      }
    }
    for (final transform in transforms) {
      final field = transform['fieldPath'] as String;
      final increment = int.parse(
        (transform['increment'] as Map)['integerValue'] as String,
      );
      final previousValue =
          int.tryParse(
            (nextFields[field] as Map?)?['integerValue'] as String? ?? '',
          ) ??
          0;
      nextFields[field] = {'integerValue': '${previousValue + increment}'};
    }
    if (previous != null &&
        jsonEncode(previous['fields']) == jsonEncode(nextFields)) {
      return;
    }
    documents[name] = <String, Object?>{
      ...document,
      'fields': nextFields,
      'updateTime': DateTime.utc(
        2026,
        9,
        19,
      ).add(Duration(microseconds: ++_version)).toIso8601String(),
    };
  }

  Future<http.Response> handle(http.Request request) async {
    await beforeRequest?.call(request);
    final path = request.url.path.replaceFirst('/v1/', '');
    if (request.method == 'POST' && path.endsWith('/documents:runQuery')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final query = body['structuredQuery'] as Map<String, dynamic>;
      final from = (query['from'] as List).single as Map<String, dynamic>;
      final collectionId = from['collectionId'] as String;
      final fieldFilter = ((query['where'] as Map?)?['fieldFilter'] as Map?)
          ?.cast<String, dynamic>();
      final fieldPath =
          ((fieldFilter?['field'] as Map?)?['fieldPath']) as String?;
      final operator = fieldFilter?['op'] as String? ?? 'EQUAL';
      final expected = fieldFilter?['value'];
      final limit = query['limit'] as int?;
      final matchingEntries = documents.entries
          .where((entry) {
            final segments = entry.key.split('/');
            final inCollection =
                segments.length >= 2 &&
                segments[segments.length - 2] == collectionId;
            if (!inCollection) return false;
            if (fieldPath == null) return true;
            final fields = entry.value['fields'] as Map<String, dynamic>?;
            final actual = fields?[fieldPath];
            if (operator == 'LESS_THAN_OR_EQUAL') {
              final actualTime = DateTime.parse(
                (actual as Map<String, dynamic>)['timestampValue'] as String,
              );
              final expectedTime = DateTime.parse(
                (expected as Map<String, dynamic>)['timestampValue'] as String,
              );
              return !actualTime.isAfter(expectedTime);
            }
            return jsonEncode(actual) == jsonEncode(expected);
          })
          .take(limit ?? documents.length);
      final matches = matchingEntries
          .map(
            (entry) => <String, Object?>{
              'document': <String, Object?>{'name': entry.key, ...entry.value},
            },
          )
          .toList(growable: false);
      return http.Response(
        jsonEncode(matches),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && path.endsWith('/documents:batchGet')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final names = (body['documents'] as List).cast<String>();
      final found = names
          .map((name) {
            final document = documents[name];
            return document == null
                ? <String, Object?>{'missing': name}
                : <String, Object?>{
                    'found': <String, Object?>{'name': name, ...document},
                  };
          })
          .toList(growable: false);
      return http.Response(
        jsonEncode(found),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && path.endsWith('/documents:commit')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final writes = (body['writes'] as List).cast<Map<String, dynamic>>();
      await beforeCommit?.call(writes);
      // Firestore commit validates the complete write set before mutating any
      // document. Model that atomicity and server-generated versions here.
      for (final write in writes) {
        final update = write['update'] as Map<String, dynamic>?;
        final name = (update?['name'] ?? write['delete']) as String;
        final precondition = write['currentDocument'] as Map<String, dynamic>?;
        final current = documents[name];
        final exists = precondition?['exists'] as bool?;
        final version = precondition?['updateTime'] as String?;
        if ((exists != null && exists != (current != null)) ||
            (version != null && version != current?['updateTime'])) {
          preconditionConflicts++;
          return _error(400, reason: 'FAILED_PRECONDITION');
        }
      }
      for (final write in writes) {
        final delete = write['delete'] as String?;
        if (delete != null) {
          documents.remove(delete);
        } else {
          final document = (write['update'] as Map).cast<String, Object?>();
          final mask = ((write['updateMask'] as Map?)?['fieldPaths'] as List?)
              ?.cast<String>();
          _writeDocument(
            document['name'] as String,
            document,
            mask: mask,
            transforms: (write['updateTransforms'] as List? ?? [])
                .cast<Map<String, dynamic>>(),
          );
        }
      }
      return _json(<String, Object?>{'writeResults': <Object?>[]});
    }

    final resourceName = path;
    if (request.method == 'GET' && resourceName.endsWith('/alerts')) {
      final prefix = '$resourceName/';
      final listed = documents.entries
          .where((entry) => entry.key.startsWith(prefix))
          .map((entry) => <String, Object?>{'name': entry.key, ...entry.value})
          .toList(growable: false);
      return _json(<String, Object?>{'documents': listed});
    }

    if (request.method == 'POST' &&
        request.url.queryParameters.containsKey('documentId')) {
      final id = request.url.queryParameters['documentId']!;
      final name = '$resourceName/$id';
      if (documents.containsKey(name)) return _error(409);
      final document = jsonDecode(request.body) as Map<String, Object?>;
      if (document.containsKey('name')) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 400,
              'message': 'document.name must not be set',
              'status': 'INVALID_ARGUMENT',
            },
          }),
          400,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      _writeDocument(name, document);
      return _json(<String, Object?>{'name': name, ...documents[name]!});
    }

    if (request.method == 'GET') {
      final document = documents[resourceName];
      if (document == null) return _error(404);
      return _json(<String, Object?>{'name': resourceName, ...document});
    }
    if (request.method == 'PATCH') {
      final document = jsonDecode(request.body) as Map<String, Object?>;
      final exists = request.url.queryParameters['currentDocument.exists'];
      final version = request.url.queryParameters['currentDocument.updateTime'];
      if ((exists != null &&
              (exists == 'true') != documents.containsKey(resourceName)) ||
          (version != null &&
              version != documents[resourceName]?['updateTime'])) {
        preconditionConflicts++;
        return _error(400, reason: 'FAILED_PRECONDITION');
      }
      _writeDocument(
        resourceName,
        document,
        mask: request.url.queryParametersAll['updateMask.fieldPaths'],
      );
      return _json(<String, Object?>{
        'name': resourceName,
        ...documents[resourceName]!,
      });
    }
    if (request.method == 'DELETE') {
      final version = request.url.queryParameters['currentDocument.updateTime'];
      if (version != null &&
          version != documents[resourceName]?['updateTime']) {
        preconditionConflicts++;
        return _error(400, reason: 'FAILED_PRECONDITION');
      }
      if (documents.remove(resourceName) == null) return _error(404);
      return _json(const <String, Object?>{});
    }
    return _error(405);
  }

  http.Response _json(Map<String, Object?> value) => http.Response(
    jsonEncode(value),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );

  http.Response _error(int status, {String? reason}) => http.Response(
    jsonEncode(<String, Object?>{
      'error': <String, Object?>{
        'code': status,
        'message': 'fake Firestore error',
        'status': reason ?? (status == 404 ? 'NOT_FOUND' : 'ALREADY_EXISTS'),
      },
    }),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
