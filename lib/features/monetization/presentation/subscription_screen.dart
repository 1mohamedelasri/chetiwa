import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/usage_quota_controller.dart';
import '../domain/premium_entitlement.dart';

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
      if (mounted) context.read<EntitlementController>().loadProducts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final entitlement = context.watch<EntitlementController>();
    final quota = context.watch<UsageQuotaController>().radarSessions;
    final resetDate =
        '${quota.resetAt.day.toString().padLeft(2, '0')}/'
        '${quota.resetAt.month.toString().padLeft(2, '0')}';
    if (entitlement.isPremium) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chetiwa+')),
        body: const Center(child: Text('Chetiwa+ est actif sur ce compte.')),
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
            'Chetiwa+ ajoute plusieurs lieux nommés, davantage d’historique Radar et supprime les publicités.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Radar ce mois-ci : ${quota.used}/${quota.limit} sessions · remise à zéro le $resetDate',
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
