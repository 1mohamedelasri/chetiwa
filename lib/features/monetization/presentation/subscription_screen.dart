import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/premium_entitlement.dart';
import '../application/app_feature_flag_controller.dart';

final class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

final class _SubscriptionScreenState extends State<SubscriptionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          context.read<AppFeatureFlagController>().premiumAvailable) {
        context.read<EntitlementController>().loadProducts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = context.watch<EntitlementController>();
    if (entitlement.isPremium) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chetiwa+')),
        body: const Center(child: Text('Chetiwa+ est actif sur ce compte.')),
      );
    }
    if (!context.watch<AppFeatureFlagController>().premiumAvailable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chetiwa+')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chetiwa+ sera proposé progressivement. Le Radar et la météo essentiels restent gratuits.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Chetiwa+')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.workspace_premium, size: 64),
          const SizedBox(height: 16),
          Text(
            'La météo essentielle reste gratuite.',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Chetiwa+ ajoute la prévision pluie étendue de 60 à 120 min, extrapolée toutes les 10 minutes à partir du déplacement radar. Il ajoute aussi plusieurs lieux nommés, davantage d’historique Radar et supprime les publicités. Le fond satellite, le Radar réel et son nowcast jusqu’à 60 min restent gratuits pour tous.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          for (final product in entitlement.products)
            Card(
              child: ListTile(
                title: Text(product.title),
                subtitle: Text(product.price),
                trailing: FilledButton(
                  onPressed: entitlement.status == PremiumPurchaseStatus.loading
                      ? null
                      : () => entitlement.purchase(product.id),
                  child: const Text('Choisir'),
                ),
              ),
            ),
          if (entitlement.products.isEmpty &&
              entitlement.status != PremiumPurchaseStatus.loading)
            const Text(
              'Les offres sont indisponibles pour le moment. Réessayez depuis un appareil configuré avec les stores.',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: entitlement.status == PremiumPurchaseStatus.loading
                ? null
                : entitlement.restorePurchases,
            child: const Text('Restaurer mes achats'),
          ),
        ],
      ),
    );
  }
}
