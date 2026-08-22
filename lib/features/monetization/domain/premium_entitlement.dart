import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumPurchaseStatus {
  idle,
  loading,
  purchased,
  restored,
  unavailable,
  failed,
}

final class PremiumProduct {
  const PremiumProduct({
    required this.id,
    required this.title,
    required this.price,
  });

  final String id;
  final String title;
  final String price;
}

final class PremiumPurchaseUpdate {
  const PremiumPurchaseUpdate({required this.productId, required this.status});

  final String productId;
  final PremiumPurchaseStatus status;
}

abstract interface class PremiumPurchaseGateway {
  Stream<PremiumPurchaseUpdate> get updates;
  Future<List<PremiumProduct>> products();
  Future<void> purchase(String productId);
  Future<void> restore();
  Future<void> dispose();
}

final class EntitlementController extends ChangeNotifier {
  EntitlementController({
    required PremiumPurchaseGateway gateway,
    bool persist = true,
    bool autoSync = true,
  }) : _gateway = gateway,
       _persist = persist {
    _subscription = gateway.updates.listen(_handleUpdate);
    if (autoSync) unawaited(_restore());
  }

  static const monthlyProductId = 'chetiwa_plus_monthly';
  static const yearlyProductId = 'chetiwa_plus_yearly';
  static const _premiumKey = 'monetization:premium:v1';

  final PremiumPurchaseGateway _gateway;
  final bool _persist;
  late final StreamSubscription<PremiumPurchaseUpdate> _subscription;
  bool _isPremium = false;
  PremiumPurchaseStatus _status = PremiumPurchaseStatus.idle;
  List<PremiumProduct> _products = const [];

  bool get isPremium => _isPremium;
  PremiumPurchaseStatus get status => _status;
  List<PremiumProduct> get products => List.unmodifiable(_products);

  Future<void> loadProducts() async {
    _status = PremiumPurchaseStatus.loading;
    notifyListeners();
    try {
      _products = await _gateway.products();
      _status = _products.isEmpty
          ? PremiumPurchaseStatus.unavailable
          : PremiumPurchaseStatus.idle;
    } on Object {
      _status = PremiumPurchaseStatus.unavailable;
    }
    notifyListeners();
  }

  Future<void> purchase(String productId) async {
    _status = PremiumPurchaseStatus.loading;
    notifyListeners();
    try {
      await _gateway.purchase(productId);
    } on Object {
      _status = PremiumPurchaseStatus.failed;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    _status = PremiumPurchaseStatus.loading;
    notifyListeners();
    try {
      await _gateway.restore();
    } on Object {
      _status = PremiumPurchaseStatus.failed;
      notifyListeners();
    }
  }

  Future<void> setFixturePremium(bool value) async {
    _setPremium(
      value,
      value ? PremiumPurchaseStatus.purchased : PremiumPurchaseStatus.idle,
    );
    await _persistValue();
  }

  Future<void> _restore() async {
    if (_persist) {
      final preferences = await SharedPreferences.getInstance();
      _isPremium = preferences.getBool(_premiumKey) ?? false;
      notifyListeners();
    }
    await restorePurchases();
  }

  void _handleUpdate(PremiumPurchaseUpdate update) {
    if (update.productId != monthlyProductId &&
        update.productId != yearlyProductId) {
      return;
    }
    if (update.status == PremiumPurchaseStatus.purchased ||
        update.status == PremiumPurchaseStatus.restored) {
      _setPremium(true, update.status);
      unawaited(_persistValue());
    } else {
      _status = update.status;
      notifyListeners();
    }
  }

  void _setPremium(bool value, PremiumPurchaseStatus status) {
    _isPremium = value;
    _status = status;
    notifyListeners();
  }

  Future<void> _persistValue() async {
    if (!_persist) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_premiumKey, _isPremium);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_gateway.dispose());
    super.dispose();
  }
}

final class FixturePremiumPurchaseGateway implements PremiumPurchaseGateway {
  FixturePremiumPurchaseGateway({bool premium = false}) : _premium = premium;

  final StreamController<PremiumPurchaseUpdate> _updates =
      StreamController<PremiumPurchaseUpdate>.broadcast();
  bool _premium;

  @override
  Stream<PremiumPurchaseUpdate> get updates => _updates.stream;

  @override
  Future<List<PremiumProduct>> products() async => const [
    PremiumProduct(
      id: EntitlementController.monthlyProductId,
      title: 'Chetiwa+ Mensuel',
      price: '1,49 €',
    ),
    PremiumProduct(
      id: EntitlementController.yearlyProductId,
      title: 'Chetiwa+ Annuel',
      price: '9,99 €',
    ),
  ];

  @override
  Future<void> purchase(String productId) async {
    _premium = true;
    _updates.add(
      PremiumPurchaseUpdate(
        productId: productId,
        status: PremiumPurchaseStatus.purchased,
      ),
    );
  }

  @override
  Future<void> restore() async {
    if (_premium) {
      _updates.add(
        const PremiumPurchaseUpdate(
          productId: EntitlementController.yearlyProductId,
          status: PremiumPurchaseStatus.restored,
        ),
      );
    }
  }

  @override
  Future<void> dispose() => _updates.close();
}
