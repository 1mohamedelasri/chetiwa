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

  Future<http.Response> handle(http.Request request) async {
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
      final expected = fieldFilter?['value'];
      final matches = documents.entries
          .where((entry) {
            final segments = entry.key.split('/');
            final inCollection =
                segments.length >= 2 &&
                segments[segments.length - 2] == collectionId;
            if (!inCollection) return false;
            if (fieldPath == null) return true;
            final fields = entry.value['fields'] as Map<String, dynamic>?;
            return jsonEncode(fields?[fieldPath]) == jsonEncode(expected);
          })
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
      for (final write in body['writes'] as List<dynamic>) {
        final delete = (write as Map<String, dynamic>)['delete'] as String?;
        if (delete != null) documents.remove(delete);
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
      documents[name] = document;
      return _json(<String, Object?>{'name': name, ...document});
    }

    if (request.method == 'GET') {
      final document = documents[resourceName];
      if (document == null) return _error(404);
      return _json(<String, Object?>{'name': resourceName, ...document});
    }
    if (request.method == 'PATCH') {
      final document = jsonDecode(request.body) as Map<String, Object?>;
      if (request.url.queryParameters['currentDocument.exists'] == 'true' &&
          !documents.containsKey(resourceName)) {
        return _error(404);
      }
      documents[resourceName] = document;
      return _json(<String, Object?>{'name': resourceName, ...document});
    }
    if (request.method == 'DELETE') {
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

  http.Response _error(int status) => http.Response(
    jsonEncode(<String, Object?>{
      'error': <String, Object?>{
        'code': status,
        'message': 'fake Firestore error',
        'status': status == 404 ? 'NOT_FOUND' : 'ALREADY_EXISTS',
      },
    }),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
