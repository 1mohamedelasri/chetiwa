import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'rain_alert_operations.dart';

final class BillingBudgetUpdate {
  const BillingBudgetUpdate({
    required this.costCents,
    required this.costIntervalStart,
    required this.currencyCode,
  });

  final int costCents;
  final DateTime costIntervalStart;
  final String currencyCode;

  static BillingBudgetUpdate parsePubSubEnvelope(
    Map<String, Object?> envelope, {
    required String expectedCurrency,
  }) {
    final message = envelope['message'];
    if (message is! Map<String, Object?>) {
      throw const FormatException('Missing Pub/Sub message');
    }
    final attributes = message['attributes'];
    if (attributes is Map<String, Object?>) {
      final schema = attributes['schemaVersion'];
      if (schema != null && schema != '1.0') {
        throw FormatException('Unsupported budget schema: $schema');
      }
    }
    final encoded = message['data'];
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException('Missing Pub/Sub data');
    }
    final decoded = jsonDecode(utf8.decode(base64.decode(encoded)));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid budget payload');
    }
    final rawCost = decoded['costAmount'];
    final cost = rawCost is num ? rawCost.toDouble() : double.nan;
    if (!cost.isFinite || cost < 0) {
      throw const FormatException('Invalid budget cost');
    }
    final currency = decoded['currencyCode']?.toString().toUpperCase();
    if (currency != expectedCurrency.toUpperCase()) {
      throw FormatException('Unexpected budget currency: $currency');
    }
    final intervalStart = DateTime.tryParse(
      decoded['costIntervalStart']?.toString() ?? '',
    );
    if (intervalStart == null) {
      throw const FormatException('Invalid cost interval');
    }
    return BillingBudgetUpdate(
      costCents: (cost * 100).round(),
      costIntervalStart: intervalStart.toUtc(),
      currencyCode: currency!,
    );
  }
}

Handler createRainAlertBudgetGuard({
  required RainAlertOperationsStore store,
  required RainAlertRuntimeControl fallbackControl,
  required String expectedCurrency,
}) {
  final router = Router();
  router.get('/healthz', (Request request) => Response.ok('ok'));
  router.post('/', (Request request) async {
    try {
      final length = request.contentLength;
      if (length != null && length > 65536) {
        return Response(413, body: 'payload_too_large');
      }
      final raw = await request.readAsString();
      if (raw.length > 65536) return Response(413, body: 'payload_too_large');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Invalid Pub/Sub envelope');
      }
      final update = BillingBudgetUpdate.parsePubSubEnvelope(
        decoded,
        expectedCurrency: expectedCurrency,
      );
      await store.updateObservedCost(
        observedCostCents: update.costCents,
        costIntervalStart: update.costIntervalStart,
        fallback: fallbackControl,
      );
      return Response(204);
    } on FormatException {
      return Response(400, body: 'invalid_budget_notification');
    }
  });
  return router.call;
}
