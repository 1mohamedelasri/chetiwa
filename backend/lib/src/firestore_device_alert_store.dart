import 'dart:math';

import 'package:googleapis/firestore/v1.dart' as firestore;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'device_alert_store.dart';
import 'rain_alert_engine.dart';
import 'rain_alert_operations.dart';

/// Persistent device and alert storage for staging and production.
///
/// Devices are addressed only by the SHA-256 owner hash already produced by
/// the HTTP layer. Alert rules live in a subcollection so every operation is
/// naturally scoped to the installation owner.
final class FirestoreDeviceAlertStore
    implements
        DeviceAlertStore,
        RainAlertEngineStore,
        RainAlertOperationsStore {
  FirestoreDeviceAlertStore({
    required firestore.FirestoreApi api,
    required String projectId,
    String databaseId = '(default)',
    DateTime Function()? now,
    String Function()? idGenerator,
    this.maximumAlertsPerDevice = 5,
    this.inactiveDeviceTtl = const Duration(days: 180),
    this.rainAlertCellSizeDegrees = 0.05,
    http.Client? ownedClient,
  }) : _api = api,
       _database = 'projects/$projectId/databases/$databaseId',
       _documents = 'projects/$projectId/databases/$databaseId/documents',
       _now = now ?? DateTime.now,
       _idGenerator = idGenerator ?? _secureId,
       _ownedClient = ownedClient;

  static Future<FirestoreDeviceAlertStore> connect({
    required String projectId,
    String databaseId = '(default)',
    double rainAlertCellSizeDegrees = 0.05,
  }) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: const <String>[firestore.FirestoreApi.datastoreScope],
    );
    return FirestoreDeviceAlertStore(
      api: firestore.FirestoreApi(client),
      projectId: projectId,
      databaseId: databaseId,
      rainAlertCellSizeDegrees: rainAlertCellSizeDegrees,
      ownedClient: client,
    );
  }

  final firestore.FirestoreApi _api;
  final String _database;
  final String _documents;
  final DateTime Function() _now;
  final String Function() _idGenerator;
  final http.Client? _ownedClient;
  final int maximumAlertsPerDevice;
  final Duration inactiveDeviceTtl;
  final double rainAlertCellSizeDegrees;

  Future<void> close() async => _ownedClient?.close();

  @override
  Future<RainAlertRuntimeControl> loadRuntimeControl(
    RainAlertRuntimeControl fallback,
  ) => _translate(() async {
    final document = await _getOrNull(_runtimeControlName);
    if (document == null) return fallback;
    return _runtimeControl(document.fields, fallback);
  });

  @override
  Future<void> recordRunMetric(RainAlertRunMetric metric) =>
      _translate(() async {
        final name = '$_documents/alertRunMetrics/${metric.runId}';
        await _api.projects.databases.documents.patch(
          firestore.Document(
            name: name,
            fields: <String, firestore.Value>{
              'runId': _string(metric.runId),
              'startedAt': _timestamp(metric.startedAt),
              'durationMilliseconds': _integer(metric.durationMilliseconds),
              'mode': _string(metric.mode),
              'status': _string(metric.status),
              'activeAlerts': _integer(metric.activeAlerts),
              'cellsEvaluated': _integer(metric.cellsEvaluated),
              'cellsSkipped': _integer(metric.cellsSkipped),
              'providerFailures': _integer(metric.providerFailures),
              'alertsEvaluated': _integer(metric.alertsEvaluated),
              'deliveriesProposed': _integer(metric.deliveriesProposed),
              'deliveriesEnqueued': _integer(metric.deliveriesEnqueued),
              'pushPending': _integer(metric.pushPending),
              'pushSent': _integer(metric.pushSent),
              'pushRetried': _integer(metric.pushRetried),
              'pushFailed': _integer(metric.pushFailed),
              'invalidTokens': _integer(metric.invalidTokens),
              'expiresAt': _timestamp(
                metric.startedAt.toUtc().add(const Duration(days: 30)),
              ),
            },
          ),
          name,
        );
      });

  @override
  Future<RainAlertRuntimeControl> updateObservedCost({
    required int observedCostCents,
    required DateTime costIntervalStart,
    required RainAlertRuntimeControl fallback,
  }) => _translate(() async {
    final existingDocument = await _getOrNull(_runtimeControlName);
    final existingFields = existingDocument?.fields;
    final hasEngineOverride =
        existingFields?.containsKey('engineEnabled') ?? false;
    final hasSendOverride = existingFields?.containsKey('sendEnabled') ?? false;
    final existing = existingDocument == null
        ? fallback
        : _runtimeControl(existingFields, fallback);
    final incomingInterval = costIntervalStart.toUtc();
    final existingInterval = existing.costIntervalStart;
    final isOlder =
        existingInterval != null && incomingInterval.isBefore(existingInterval);
    if (isOlder) return existing;
    final cost =
        existingInterval != null &&
            incomingInterval.isAtSameMomentAs(existingInterval)
        ? max(existing.observedCostCents, observedCostCents)
        : observedCostCents;
    final hardExceeded = cost >= existing.hardBudgetCents;
    final updatedAt = _now().toUtc();
    final updated = RainAlertRuntimeControl(
      engineEnabled: hardExceeded ? false : existing.engineEnabled,
      sendEnabled: hardExceeded ? false : existing.sendEnabled,
      observedCostCents: cost,
      softBudgetCents: existing.softBudgetCents,
      hardBudgetCents: existing.hardBudgetCents,
      costIntervalStart: incomingInterval,
      updatedAt: updatedAt,
    );
    await _api.projects.databases.documents.patch(
      firestore.Document(
        name: _runtimeControlName,
        fields: <String, firestore.Value>{
          if (hardExceeded || hasEngineOverride)
            'engineEnabled': _boolean(updated.engineEnabled),
          if (hardExceeded || hasSendOverride)
            'sendEnabled': _boolean(updated.sendEnabled),
          'observedCostCents': _integer(updated.observedCostCents),
          'softBudgetCents': _integer(updated.softBudgetCents),
          'hardBudgetCents': _integer(updated.hardBudgetCents),
          'softBudgetExceeded': _boolean(updated.softBudgetExceeded),
          'hardBudgetExceeded': _boolean(updated.hardBudgetExceeded),
          'costIntervalStart': _timestamp(incomingInterval),
          'updatedAt': _timestamp(updatedAt),
        },
      ),
      _runtimeControlName,
    );
    return updated;
  });

  RainAlertRuntimeControl _runtimeControl(
    Map<String, firestore.Value>? rawFields,
    RainAlertRuntimeControl fallback,
  ) {
    final fields = rawFields ?? const <String, firestore.Value>{};
    return RainAlertRuntimeControl(
      engineEnabled:
          fields['engineEnabled']?.booleanValue ?? fallback.engineEnabled,
      sendEnabled: fields['sendEnabled']?.booleanValue ?? fallback.sendEnabled,
      observedCostCents:
          _readOptionalInteger(fields, 'observedCostCents') ??
          fallback.observedCostCents,
      softBudgetCents:
          _readOptionalInteger(fields, 'softBudgetCents') ??
          fallback.softBudgetCents,
      hardBudgetCents:
          _readOptionalInteger(fields, 'hardBudgetCents') ??
          fallback.hardBudgetCents,
      costIntervalStart:
          _readOptionalTimestamp(fields, 'costIntervalStart') ??
          fallback.costIntervalStart,
      updatedAt:
          _readOptionalTimestamp(fields, 'updatedAt') ?? fallback.updatedAt,
    );
  }

  @override
  Future<bool> acquireLease({
    required String runId,
    required DateTime now,
    required DateTime expiresAt,
  }) => _translate(() async {
    final name = '$_documents/alertEngineLeases/active';
    final existing = await _getOrNull(name);
    if (existing != null) {
      final fields = existing.fields ?? const <String, firestore.Value>{};
      final existingExpiry = _readTimestamp(fields, 'expiresAt');
      if (existingExpiry.isAfter(now.toUtc())) return false;
      try {
        await _api.projects.databases.documents.delete(name);
      } on firestore.DetailedApiRequestError catch (error) {
        if (error.status != 404) rethrow;
      }
    }
    try {
      await _api.projects.databases.documents.createDocument(
        firestore.Document(
          name: name,
          fields: <String, firestore.Value>{
            'runId': _string(runId),
            'createdAt': _timestamp(now),
            'expiresAt': _timestamp(expiresAt),
          },
        ),
        _documents,
        'alertEngineLeases',
        documentId: 'active',
      );
      return true;
    } on firestore.DetailedApiRequestError catch (error) {
      if (error.status == 409) return false;
      rethrow;
    }
  });

  @override
  Future<void> releaseLease(String runId) => _translate(() async {
    final name = '$_documents/alertEngineLeases/active';
    final existing = await _getOrNull(name);
    if (existing == null) return;
    final fields = existing.fields ?? const <String, firestore.Value>{};
    if (_readString(fields, 'runId') != runId) return;
    await _api.projects.databases.documents.delete(name);
  });

  @override
  Future<List<ActiveRainAlert>> listActiveAlerts() => _translate(() async {
    final alertDocuments = await _query(
      collectionId: 'alerts',
      allDescendants: true,
      field: 'enabled',
      value: _boolean(true),
    );
    final rules = alertDocuments.map(_alertRecord).toList(growable: false);
    return _activeAlertsForRules(rules);
  });

  Future<List<ActiveRainAlert>> _activeAlertsForRules(
    List<AlertRuleRecord> rules,
  ) async {
    final names = <String>{
      for (final rule in rules) _deviceName(rule.ownerHash),
      for (final rule in rules) _stateName(rule.ownerHash, rule.id),
    };
    final related = await _batchGet(names);
    final active = <ActiveRainAlert>[];
    for (final rule in rules) {
      final deviceDocument = related[_deviceName(rule.ownerHash)];
      if (deviceDocument == null) continue;
      final device = _deviceRecord(rule.ownerHash, deviceDocument);
      final stateDocument = related[_stateName(rule.ownerHash, rule.id)];
      active.add(
        ActiveRainAlert(
          device: device,
          rule: rule,
          state: stateDocument == null
              ? RainAlertState(ownerHash: rule.ownerHash, alertId: rule.id)
              : _rainAlertState(rule.ownerHash, rule.id, stateDocument),
        ),
      );
    }
    return active;
  }

  @override
  Future<List<RainAlertCellSchedule>> listDueCellSchedules({
    required DateTime now,
    int limit = 500,
  }) => _translate(() async {
    final documents = await _query(
      collectionId: 'alertCellSchedules',
      field: 'nextCheckAt',
      operator: 'LESS_THAN_OR_EQUAL',
      value: _timestamp(now),
      limit: limit,
    );
    return documents.map(_cellSchedule).toList(growable: false);
  });

  @override
  Future<List<ActiveRainAlert>> listActiveAlertsForCell(String cellKey) =>
      _translate(() async {
        final documents = await _query(
          collectionId: 'alerts',
          allDescendants: true,
          field: 'cellKey',
          value: _string(cellKey),
        );
        final rules = documents
            .map(_alertRecord)
            .where((rule) => rule.enabled)
            .toList(growable: false);
        return _activeAlertsForRules(rules);
      });

  @override
  Future<void> saveCellSchedule(RainAlertCellSchedule schedule) =>
      _translate(() async {
        final name = _cellScheduleName(schedule.cellKey);
        await _api.projects.databases.documents.patch(
          firestore.Document(
            name: name,
            fields: <String, firestore.Value>{
              'cellKey': _string(schedule.cellKey),
              'latitude': _double(schedule.latitude),
              'longitude': _double(schedule.longitude),
              'nextCheckAt': _timestamp(schedule.nextCheckAt),
              'lastCheckedAt': _timestamp(schedule.lastCheckedAt),
              'mode': _string(schedule.mode.name),
              // Firestore TTL removes state shortly after a cell no longer has
              // an active rule. The engine itself never polls inactive cells.
              'expiresAt': _timestamp(
                schedule.lastCheckedAt.add(const Duration(days: 7)),
              ),
            },
          ),
          name,
        );
      });

  @override
  Future<void> deleteCellSchedule(String cellKey) => _translate(() async {
    try {
      await _api.projects.databases.documents.delete(
        _cellScheduleName(cellKey),
      );
    } on firestore.DetailedApiRequestError catch (error) {
      if (error.status != 404) rethrow;
    }
  });

  @override
  Future<void> saveState(RainAlertState state) => _translate(() async {
    await _api.projects.databases.documents.patch(
      _stateDocument(state),
      _stateName(state.ownerHash, state.alertId),
    );
  });

  @override
  Future<bool> enqueueDelivery(AlertDeliveryDraft delivery) =>
      _translate(() async {
        try {
          await _api.projects.databases.documents.createDocument(
            _deliveryDocument(delivery),
            _documents,
            'alertDeliveries',
            documentId: delivery.eventId,
          );
          return true;
        } on firestore.DetailedApiRequestError catch (error) {
          if (error.status == 409) return false;
          rethrow;
        }
      });

  @override
  Future<List<PendingAlertDelivery>> listPendingDeliveries({int limit = 500}) =>
      _translate(() async {
        final deliveryDocuments = await _query(
          collectionId: 'alertDeliveries',
          field: 'status',
          value: _string(AlertDeliveryStatus.pending.name),
          limit: limit,
        );
        final drafts = deliveryDocuments
            .map(_pendingDeliveryFields)
            .toList(growable: false);
        final deviceDocuments = await _batchGet(
          drafts.map((item) => _deviceName(item.draft.ownerHash)).toSet(),
        );
        final pending = <PendingAlertDelivery>[];
        for (final item in drafts) {
          final deviceDocument =
              deviceDocuments[_deviceName(item.draft.ownerHash)];
          if (deviceDocument == null) continue;
          final device = _deviceRecord(item.draft.ownerHash, deviceDocument);
          final token = device.pushToken;
          if (!device.notificationsEnabled || token == null || token.isEmpty) {
            continue;
          }
          pending.add(
            PendingAlertDelivery(
              draft: item.draft,
              pushToken: token,
              platform: device.platform,
              attempts: item.attempts,
              nextAttemptAt: item.nextAttemptAt,
            ),
          );
        }
        return pending;
      });

  @override
  Future<void> markDeliverySent(String eventId, DateTime sentAt) =>
      _updateDelivery(eventId, <String, firestore.Value>{
        'status': _string(AlertDeliveryStatus.sent.name),
        'sentAt': _timestamp(sentAt),
        'updatedAt': _timestamp(sentAt),
      });

  @override
  Future<void> retryDelivery(
    String eventId, {
    required int attempts,
    required DateTime nextAttemptAt,
  }) => _updateDelivery(eventId, <String, firestore.Value>{
    'attempts': _integer(attempts),
    'nextAttemptAt': _timestamp(nextAttemptAt),
    'updatedAt': _timestamp(_now().toUtc()),
  });

  @override
  Future<void> failDelivery(String eventId, String reason) =>
      _updateDelivery(eventId, <String, firestore.Value>{
        'status': _string(AlertDeliveryStatus.permanentFailure.name),
        'failureReason': _string(reason),
        'updatedAt': _timestamp(_now().toUtc()),
      });

  @override
  Future<void> disableDeviceToken(String ownerHash) => _translate(() async {
    final existing = await _device(ownerHash);
    if (existing == null) return;
    final disabled = DeviceRecord(
      ownerHash: existing.ownerHash,
      platform: existing.platform,
      locale: existing.locale,
      timeZone: existing.timeZone,
      notificationsEnabled: false,
      appVersion: existing.appVersion,
      createdAt: existing.createdAt,
      updatedAt: _now().toUtc(),
      expiresAt: existing.expiresAt,
    );
    await _api.projects.databases.documents.patch(
      _deviceDocument(disabled),
      _deviceName(ownerHash),
      currentDocument_exists: true,
    );
  });

  @override
  Future<DeviceRecord> upsertDevice(
    String ownerHash,
    DeviceRegistration registration,
  ) => _translate(() => _upsertDevice(ownerHash, registration));

  Future<DeviceRecord> _upsertDevice(
    String ownerHash,
    DeviceRegistration registration,
  ) async {
    final existing = await _device(ownerHash);
    final instant = _now().toUtc();
    final record = DeviceRecord(
      ownerHash: ownerHash,
      platform: registration.platform,
      locale: registration.locale,
      timeZone: registration.timeZone,
      notificationsEnabled: registration.notificationsEnabled,
      pushToken: registration.notificationsEnabled
          ? registration.pushToken
          : null,
      appVersion: registration.appVersion,
      createdAt: existing?.createdAt ?? instant,
      updatedAt: instant,
      expiresAt: instant.add(inactiveDeviceTtl),
    );
    await _api.projects.databases.documents.patch(
      _deviceDocument(record),
      _deviceName(ownerHash),
    );
    return record;
  }

  @override
  Future<bool> deleteDevice(String ownerHash) =>
      _translate(() => _deleteDevice(ownerHash));

  Future<bool> _deleteDevice(String ownerHash) async {
    if (await _device(ownerHash) == null) return false;
    final alerts = await _listAlertDocuments(ownerHash);
    final affectedCellKeys = alerts
        .map(_alertRecord)
        .map(
          (alert) => RainAlertCell.fromLocation(
            alert.location,
            sizeDegrees: rainAlertCellSizeDegrees,
          ).key,
        )
        .toSet();
    final deliveries = await _query(
      collectionId: 'alertDeliveries',
      field: 'ownerHash',
      value: _string(ownerHash),
    );
    final names = <String>[
      ...alerts.map((document) => document.name).whereType<String>(),
      ...alerts.map((document) {
        final name = document.name!;
        final alertId = name.substring(name.lastIndexOf('/') + 1);
        return _stateName(ownerHash, alertId);
      }),
      ...deliveries.map((document) => document.name).whereType<String>(),
      _deviceName(ownerHash),
    ];
    for (var offset = 0; offset < names.length; offset += 500) {
      final end = min(offset + 500, names.length);
      await _api.projects.databases.documents.commit(
        firestore.CommitRequest(
          writes: names
              .sublist(offset, end)
              .map((name) => firestore.Write(delete: name))
              .toList(growable: false),
        ),
        _database,
      );
    }
    for (final cellKey in affectedCellKeys) {
      if ((await listActiveAlertsForCell(cellKey)).isEmpty) {
        await deleteCellSchedule(cellKey);
      }
    }
    return true;
  }

  @override
  Future<List<AlertRuleRecord>> listAlerts(String ownerHash) =>
      _translate(() => _listAlerts(ownerHash));

  Future<List<AlertRuleRecord>> _listAlerts(String ownerHash) async {
    await _requireDevice(ownerHash);
    final documents = await _listAlertDocuments(ownerHash);
    final records = documents.map(_alertRecord).toList(growable: false);
    records.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return records;
  }

  @override
  Future<AlertRuleRecord> createAlert(String ownerHash, AlertRuleDraft draft) =>
      _translate(() => _createAlert(ownerHash, draft));

  Future<AlertRuleRecord> _createAlert(
    String ownerHash,
    AlertRuleDraft draft,
  ) async {
    await _requireDevice(ownerHash);
    final existing = await _listAlertDocuments(ownerHash);
    if (existing.length >= maximumAlertsPerDevice) {
      throw ApiException(
        statusCode: 409,
        code: 'alert_limit_reached',
        message: 'A maximum of $maximumAlertsPerDevice alerts is allowed',
      );
    }

    final instant = _now().toUtc();
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final id = _idGenerator();
      final record = AlertRuleRecord(
        id: id,
        ownerHash: ownerHash,
        location: draft.location,
        leadMinutes: draft.leadMinutes,
        minimumIntensity: draft.minimumIntensity,
        quietHours: draft.quietHours,
        enabled: draft.enabled,
        createdAt: instant,
        updatedAt: instant,
      );
      try {
        await _api.projects.databases.documents.createDocument(
          _alertDocument(record),
          _deviceName(ownerHash),
          'alerts',
          documentId: id,
        );
        if (record.enabled) {
          await _makeCellDue(record.location, instant);
        }
        return record;
      } on firestore.DetailedApiRequestError catch (error) {
        if (error.status != 409 || attempt == 2) rethrow;
      }
    }
    throw StateError('Could not allocate a unique alert identifier');
  }

  @override
  Future<AlertRuleRecord?> updateAlert(
    String ownerHash,
    String alertId,
    AlertRuleChanges changes,
  ) => _translate(() => _updateAlert(ownerHash, alertId, changes));

  Future<AlertRuleRecord?> _updateAlert(
    String ownerHash,
    String alertId,
    AlertRuleChanges changes,
  ) async {
    await _requireDevice(ownerHash);
    final existingDocument = await _getOrNull(_alertName(ownerHash, alertId));
    if (existingDocument == null) return null;
    final existing = _alertRecord(existingDocument);
    final record = AlertRuleRecord(
      id: existing.id,
      ownerHash: existing.ownerHash,
      location: changes.location ?? existing.location,
      leadMinutes: changes.leadMinutes ?? existing.leadMinutes,
      minimumIntensity: changes.minimumIntensity ?? existing.minimumIntensity,
      quietHours: changes.quietHours ?? existing.quietHours,
      enabled: changes.enabled ?? existing.enabled,
      createdAt: existing.createdAt,
      updatedAt: _now().toUtc(),
    );
    final existingCell = RainAlertCell.fromLocation(
      existing.location,
      sizeDegrees: rainAlertCellSizeDegrees,
    );
    final nextCell = RainAlertCell.fromLocation(
      record.location,
      sizeDegrees: rainAlertCellSizeDegrees,
    );
    final pollingRelevantChange =
        !(existingDocument.fields?.containsKey('cellKey') ?? false) ||
        existingCell.key != nextCell.key ||
        existing.leadMinutes != record.leadMinutes ||
        existing.minimumIntensity != record.minimumIntensity ||
        (!existing.enabled && record.enabled);
    final scheduleMissing =
        record.enabled &&
        !pollingRelevantChange &&
        await _getOrNull(_cellScheduleName(nextCell.key)) == null;
    if (record.enabled && (pollingRelevantChange || scheduleMissing)) {
      await _makeCellDue(record.location, record.updatedAt);
    }
    await _api.projects.databases.documents.patch(
      _alertDocument(record),
      _alertName(ownerHash, alertId),
      currentDocument_exists: true,
    );
    return record;
  }

  @override
  Future<bool> deleteAlert(String ownerHash, String alertId) =>
      _translate(() => _deleteAlert(ownerHash, alertId));

  Future<bool> _deleteAlert(String ownerHash, String alertId) async {
    await _requireDevice(ownerHash);
    final name = _alertName(ownerHash, alertId);
    if (await _getOrNull(name) == null) return false;
    await _api.projects.databases.documents.commit(
      firestore.CommitRequest(
        writes: <firestore.Write>[
          firestore.Write(delete: name),
          firestore.Write(delete: _stateName(ownerHash, alertId)),
        ],
      ),
      _database,
    );
    return true;
  }

  Future<void> _makeCellDue(AlertLocation location, DateTime now) {
    final cell = RainAlertCell.fromLocation(
      location,
      sizeDegrees: rainAlertCellSizeDegrees,
    );
    return saveCellSchedule(
      RainAlertCellSchedule(
        cellKey: cell.key,
        latitude: cell.latitude,
        longitude: cell.longitude,
        nextCheckAt: now,
        lastCheckedAt: now,
        mode: RainAlertPollingMode.retry,
      ),
    );
  }

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ApiException {
      rethrow;
    } on firestore.DetailedApiRequestError {
      throw ApiException(
        statusCode: 503,
        code: 'persistent_store_unavailable',
        message: 'Persistent device and alert storage is unavailable',
      );
    } on FormatException {
      throw const ApiException(
        statusCode: 503,
        code: 'persistent_store_invalid_data',
        message: 'Persistent device and alert storage contains invalid data',
      );
    }
  }

  Future<DeviceRecord?> _device(String ownerHash) async {
    final document = await _getOrNull(_deviceName(ownerHash));
    return document == null ? null : _deviceRecord(ownerHash, document);
  }

  Future<void> _requireDevice(String ownerHash) async {
    if (await _device(ownerHash) != null) return;
    throw const ApiException(
      statusCode: 409,
      code: 'device_not_registered',
      message: 'Register this installation before managing alerts',
    );
  }

  Future<firestore.Document?> _getOrNull(String name) async {
    try {
      return await _api.projects.databases.documents.get(name);
    } on firestore.DetailedApiRequestError catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<List<firestore.Document>> _listAlertDocuments(String ownerHash) async {
    final documents = <firestore.Document>[];
    String? pageToken;
    do {
      final response = await _api.projects.databases.documents.list(
        _deviceName(ownerHash),
        'alerts',
        pageSize: 100,
        pageToken: pageToken,
      );
      documents.addAll(response.documents ?? const <firestore.Document>[]);
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return documents;
  }

  Future<List<firestore.Document>> _query({
    required String collectionId,
    bool allDescendants = false,
    String? field,
    String operator = 'EQUAL',
    firestore.Value? value,
    int? limit,
  }) async {
    final filter = field != null && value != null
        ? firestore.Filter(
            fieldFilter: firestore.FieldFilter(
              field: firestore.FieldReference(fieldPath: field),
              op: operator,
              value: value,
            ),
          )
        : null;
    final response = await _api.projects.databases.documents.runQuery(
      firestore.RunQueryRequest(
        structuredQuery: firestore.StructuredQuery(
          from: <firestore.CollectionSelector>[
            firestore.CollectionSelector(
              collectionId: collectionId,
              allDescendants: allDescendants,
            ),
          ],
          where: filter,
          limit: limit,
        ),
      ),
      _documents,
    );
    return response
        .map((element) => element.document)
        .whereType<firestore.Document>()
        .toList(growable: false);
  }

  Future<Map<String, firestore.Document>> _batchGet(Set<String> names) async {
    if (names.isEmpty) return <String, firestore.Document>{};
    final result = <String, firestore.Document>{};
    final values = names.toList(growable: false);
    for (var offset = 0; offset < values.length; offset += 100) {
      final end = min(offset + 100, values.length);
      final response = await _api.projects.databases.documents.batchGet(
        firestore.BatchGetDocumentsRequest(
          documents: values.sublist(offset, end),
        ),
        _database,
      );
      for (final element in response) {
        final document = element.found;
        if (document?.name case final name?) result[name] = document!;
      }
    }
    return result;
  }

  Future<void> _updateDelivery(
    String eventId,
    Map<String, firestore.Value> fields,
  ) => _translate(() async {
    await _api.projects.databases.documents.patch(
      firestore.Document(name: _deliveryName(eventId), fields: fields),
      _deliveryName(eventId),
      currentDocument_exists: true,
      updateMask_fieldPaths: fields.keys.toList(growable: false),
    );
  });

  firestore.Document _stateDocument(RainAlertState state) => firestore.Document(
    name: _stateName(state.ownerHash, state.alertId),
    fields: <String, firestore.Value>{
      'ownerHash': _string(state.ownerHash),
      'alertId': _string(state.alertId),
      'rainExpected': _boolean(state.rainExpected),
      'lastIntensity': _string(state.lastIntensity.name),
      if (state.lastSentAt case final value?) 'lastSentAt': _timestamp(value),
      if (state.dailyDate case final value?) 'dailyDate': _string(value),
      'dailyCount': _integer(state.dailyCount),
      if (state.updatedAt case final value?) 'updatedAt': _timestamp(value),
      'expiresAt': _timestamp(
        (state.updatedAt ?? _now().toUtc()).add(inactiveDeviceTtl),
      ),
    },
  );

  RainAlertState _rainAlertState(
    String ownerHash,
    String alertId,
    firestore.Document document,
  ) {
    final fields = document.fields ?? const <String, firestore.Value>{};
    return RainAlertState(
      ownerHash: ownerHash,
      alertId: alertId,
      rainExpected: fields['rainExpected']?.booleanValue ?? false,
      lastIntensity: AlertRainIntensity.values.byName(
        fields['lastIntensity']?.stringValue ?? 'none',
      ),
      lastSentAt: _readOptionalTimestamp(fields, 'lastSentAt'),
      dailyDate: fields['dailyDate']?.stringValue,
      dailyCount: _readOptionalInteger(fields, 'dailyCount') ?? 0,
      updatedAt: _readOptionalTimestamp(fields, 'updatedAt'),
    );
  }

  RainAlertCellSchedule _cellSchedule(firestore.Document document) {
    final fields = document.fields ?? const <String, firestore.Value>{};
    return RainAlertCellSchedule(
      cellKey: _readString(fields, 'cellKey'),
      latitude: _readDouble(fields, 'latitude'),
      longitude: _readDouble(fields, 'longitude'),
      nextCheckAt: _readTimestamp(fields, 'nextCheckAt'),
      lastCheckedAt: _readTimestamp(fields, 'lastCheckedAt'),
      mode: RainAlertPollingMode.values.byName(_readString(fields, 'mode')),
    );
  }

  firestore.Document _deliveryDocument(AlertDeliveryDraft delivery) =>
      firestore.Document(
        name: _deliveryName(delivery.eventId),
        fields: <String, firestore.Value>{
          'eventId': _string(delivery.eventId),
          'ownerHash': _string(delivery.ownerHash),
          'alertId': _string(delivery.alertId),
          'cellKey': _string(delivery.cellKey),
          'location': _map(<String, firestore.Value>{
            'label': _string(delivery.location.label),
            'latitude': _double(delivery.location.latitude),
            'longitude': _double(delivery.location.longitude),
            'timeZone': _string(delivery.location.timeZone),
          }),
          'intensity': _string(delivery.intensity.name),
          'expectedAt': _timestamp(delivery.expectedAt),
          'title': _string(delivery.title),
          'body': _string(delivery.body),
          'status': _string(AlertDeliveryStatus.pending.name),
          'attempts': _integer(0),
          'nextAttemptAt': _timestamp(delivery.createdAt),
          'createdAt': _timestamp(delivery.createdAt),
          'updatedAt': _timestamp(delivery.createdAt),
          'expiresAt': _timestamp(delivery.expiresAt),
        },
      );

  ({AlertDeliveryDraft draft, int attempts, DateTime nextAttemptAt})
  _pendingDeliveryFields(firestore.Document document) {
    final fields = document.fields ?? const <String, firestore.Value>{};
    final location = _readMap(fields, 'location');
    return (
      draft: AlertDeliveryDraft(
        eventId: _readString(fields, 'eventId'),
        ownerHash: _readString(fields, 'ownerHash'),
        alertId: _readString(fields, 'alertId'),
        cellKey: _readString(fields, 'cellKey'),
        location: AlertLocation(
          label: _readString(location, 'label'),
          latitude: _readDouble(location, 'latitude'),
          longitude: _readDouble(location, 'longitude'),
          timeZone: _readString(location, 'timeZone'),
        ),
        intensity: AlertRainIntensity.values.byName(
          _readString(fields, 'intensity'),
        ),
        expectedAt: _readTimestamp(fields, 'expectedAt'),
        title: _readString(fields, 'title'),
        body: _readString(fields, 'body'),
        createdAt: _readTimestamp(fields, 'createdAt'),
        expiresAt: _readTimestamp(fields, 'expiresAt'),
      ),
      attempts: _readInteger(fields, 'attempts'),
      nextAttemptAt: _readTimestamp(fields, 'nextAttemptAt'),
    );
  }

  firestore.Document _deviceDocument(DeviceRecord record) => firestore.Document(
    name: _deviceName(record.ownerHash),
    fields: <String, firestore.Value>{
      'platform': _string(record.platform),
      'locale': _string(record.locale),
      'timeZone': _string(record.timeZone),
      'notificationsEnabled': _boolean(record.notificationsEnabled),
      if (record.pushToken case final token?) 'pushToken': _string(token),
      if (record.appVersion case final version?) 'appVersion': _string(version),
      'createdAt': _timestamp(record.createdAt),
      'updatedAt': _timestamp(record.updatedAt),
      'expiresAt': _timestamp(record.expiresAt),
    },
  );

  firestore.Document _alertDocument(AlertRuleRecord record) =>
      firestore.Document(
        name: _alertName(record.ownerHash, record.id),
        fields: <String, firestore.Value>{
          'ownerHash': _string(record.ownerHash),
          'cellKey': _string(
            RainAlertCell.fromLocation(
              record.location,
              sizeDegrees: rainAlertCellSizeDegrees,
            ).key,
          ),
          'location': _map(<String, firestore.Value>{
            'label': _string(record.location.label),
            'latitude': _double(record.location.latitude),
            'longitude': _double(record.location.longitude),
            'timeZone': _string(record.location.timeZone),
          }),
          'leadMinutes': _integer(record.leadMinutes),
          'minimumIntensity': _string(record.minimumIntensity),
          'quietHours': _map(<String, firestore.Value>{
            'enabled': _boolean(record.quietHours.enabled),
            'start': _string(record.quietHours.start),
            'end': _string(record.quietHours.end),
          }),
          'enabled': _boolean(record.enabled),
          'createdAt': _timestamp(record.createdAt),
          'updatedAt': _timestamp(record.updatedAt),
          'expiresAt': _timestamp(record.updatedAt.add(inactiveDeviceTtl)),
        },
      );

  DeviceRecord _deviceRecord(String ownerHash, firestore.Document document) {
    final fields = document.fields ?? const <String, firestore.Value>{};
    return DeviceRecord(
      ownerHash: ownerHash,
      platform: _readString(fields, 'platform'),
      locale: _readString(fields, 'locale'),
      timeZone: _readString(fields, 'timeZone'),
      notificationsEnabled: _readBoolean(fields, 'notificationsEnabled'),
      pushToken: fields['pushToken']?.stringValue,
      appVersion: fields['appVersion']?.stringValue,
      createdAt: _readTimestamp(fields, 'createdAt'),
      updatedAt: _readTimestamp(fields, 'updatedAt'),
      expiresAt: _readTimestamp(fields, 'expiresAt'),
    );
  }

  AlertRuleRecord _alertRecord(firestore.Document document) {
    final fields = document.fields ?? const <String, firestore.Value>{};
    final location = _readMap(fields, 'location');
    final quietHours = _readMap(fields, 'quietHours');
    final name = document.name;
    if (name == null || !name.contains('/alerts/')) {
      throw const FormatException('Invalid Firestore alert document name');
    }
    return AlertRuleRecord(
      id: name.substring(name.lastIndexOf('/') + 1),
      ownerHash: _readString(fields, 'ownerHash'),
      location: AlertLocation(
        label: _readString(location, 'label'),
        latitude: _readDouble(location, 'latitude'),
        longitude: _readDouble(location, 'longitude'),
        timeZone: _readString(location, 'timeZone'),
      ),
      leadMinutes: _readInteger(fields, 'leadMinutes'),
      minimumIntensity: _readString(fields, 'minimumIntensity'),
      quietHours: QuietHours(
        enabled: _readBoolean(quietHours, 'enabled'),
        start: _readString(quietHours, 'start'),
        end: _readString(quietHours, 'end'),
      ),
      enabled: _readBoolean(fields, 'enabled'),
      createdAt: _readTimestamp(fields, 'createdAt'),
      updatedAt: _readTimestamp(fields, 'updatedAt'),
    );
  }

  String _deviceName(String ownerHash) => '$_documents/devices/$ownerHash';

  String _alertName(String ownerHash, String alertId) =>
      '${_deviceName(ownerHash)}/alerts/$alertId';

  String _stateName(String ownerHash, String alertId) =>
      '$_documents/alertStates/${ownerHash}_$alertId';

  String _deliveryName(String eventId) =>
      '$_documents/alertDeliveries/$eventId';

  String _cellScheduleName(String cellKey) =>
      '$_documents/alertCellSchedules/$cellKey';

  String get _runtimeControlName => '$_documents/alertControl/runtime';

  static firestore.Value _string(String value) =>
      firestore.Value(stringValue: value);
  static firestore.Value _boolean(bool value) =>
      firestore.Value(booleanValue: value);
  static firestore.Value _double(double value) =>
      firestore.Value(doubleValue: value);
  static firestore.Value _integer(int value) =>
      firestore.Value(integerValue: value.toString());
  static firestore.Value _timestamp(DateTime value) =>
      firestore.Value(timestampValue: value.toUtc().toIso8601String());
  static firestore.Value _map(Map<String, firestore.Value> value) =>
      firestore.Value(mapValue: firestore.MapValue(fields: value));

  static String _readString(Map<String, firestore.Value> fields, String name) {
    final value = fields[name]?.stringValue;
    if (value == null) throw FormatException('Missing string field $name');
    return value;
  }

  static bool _readBoolean(Map<String, firestore.Value> fields, String name) {
    final value = fields[name]?.booleanValue;
    if (value == null) throw FormatException('Missing bool field $name');
    return value;
  }

  static double _readDouble(Map<String, firestore.Value> fields, String name) {
    final value = fields[name]?.doubleValue;
    if (value == null) throw FormatException('Missing double field $name');
    return value;
  }

  static int _readInteger(Map<String, firestore.Value> fields, String name) {
    final value = int.tryParse(fields[name]?.integerValue ?? '');
    if (value == null) throw FormatException('Missing integer field $name');
    return value;
  }

  static int? _readOptionalInteger(
    Map<String, firestore.Value> fields,
    String name,
  ) => int.tryParse(fields[name]?.integerValue ?? '');

  static DateTime _readTimestamp(
    Map<String, firestore.Value> fields,
    String name,
  ) {
    final value = DateTime.tryParse(fields[name]?.timestampValue ?? '');
    if (value == null) throw FormatException('Missing timestamp field $name');
    return value.toUtc();
  }

  static DateTime? _readOptionalTimestamp(
    Map<String, firestore.Value> fields,
    String name,
  ) => DateTime.tryParse(fields[name]?.timestampValue ?? '')?.toUtc();

  static Map<String, firestore.Value> _readMap(
    Map<String, firestore.Value> fields,
    String name,
  ) {
    final value = fields[name]?.mapValue?.fields;
    if (value == null) throw FormatException('Missing map field $name');
    return value;
  }

  static String _secureId() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
  }
}
