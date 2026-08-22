import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../domain/premium_entitlement.dart';

final class StorePurchaseGateway implements PremiumPurchaseGateway {
  StorePurchaseGateway({InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance {
    _subscription = _store.purchaseStream.listen(_handlePurchases);
  }

  final InAppPurchase _store;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  final StreamController<PremiumPurchaseUpdate> _updates =
      StreamController<PremiumPurchaseUpdate>.broadcast();

  @override
  Stream<PremiumPurchaseUpdate> get updates => _updates.stream;

  @override
  Future<List<PremiumProduct>> products() async {
    if (!await _store.isAvailable()) return const [];
    final response = await _store.queryProductDetails({
      EntitlementController.monthlyProductId,
      EntitlementController.yearlyProductId,
    });
    return response.productDetails
        .map(
          (product) => PremiumProduct(
            id: product.id,
            title: product.title,
            price: product.price,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> purchase(String productId) async {
    final response = await _store.queryProductDetails({productId});
    if (response.productDetails.isEmpty) {
      throw StateError('Product unavailable');
    }
    await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: response.productDetails.single,
      ),
    );
  }

  @override
  Future<void> restore() => _store.restorePurchases();

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      final status = switch (purchase.status) {
        PurchaseStatus.purchased => PremiumPurchaseStatus.purchased,
        PurchaseStatus.restored => PremiumPurchaseStatus.restored,
        PurchaseStatus.error => PremiumPurchaseStatus.failed,
        PurchaseStatus.pending => PremiumPurchaseStatus.loading,
        PurchaseStatus.canceled => PremiumPurchaseStatus.idle,
      };
      _updates.add(
        PremiumPurchaseUpdate(productId: purchase.productID, status: status),
      );
      if (purchase.pendingCompletePurchase) {
        unawaited(_store.completePurchase(purchase));
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _updates.close();
  }
}
