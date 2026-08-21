# ADR-0005 — RevenueCat derrière SubscriptionRepository

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Produit/Backend Chetiwa

## Contexte

Les abonnements iOS et Android imposent de gérer achat, restauration, expiration,
grace period, remboursement, révocation et notifications serveur. Une erreur peut
donner des accès gratuits ou bloquer un client ayant payé.

## Décision

- Utiliser RevenueCat pour le MVP afin d’unifier StoreKit et Google Play Billing.
- Cacher son SDK derrière `SubscriptionRepository`.
- Le backend conserve seulement l’entitlement Chetiwa nécessaire, pas les données
  de paiement.
- L’application doit toujours proposer « Restaurer mes achats ».
- Le backend/webhook fait foi ; un booléen local ne fait jamais foi.
- Commencer sur le plan sans coût tant que le revenu suivi reste dans son seuil,
  puis intégrer son pourcentage dans les unit economics.

## Produits initiaux

- `chetiwa_plus_monthly`.
- `chetiwa_plus_annual`, recommandé dans le paywall.
- Pas de lifetime comme modèle principal.

## Garde-fous

- Tester achats, restauration, pending, expiration, remboursement, révocation et
  changement d’appareil en sandbox.
- Vérifier les webhooks par signature et idempotence.
- Pouvoir migrer vers validation Apple/Google directe grâce au repository.

## Réévaluation

Réévaluer quand les frais RevenueCat deviennent supérieurs au coût réel d’une
validation interne fiable, ou si les exigences de données changent.

## Référence

- [RevenueCat pricing](https://www.revenuecat.com/pricing)

