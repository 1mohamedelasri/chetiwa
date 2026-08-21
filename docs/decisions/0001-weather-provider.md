# ADR-0001 — Open-Meteo pour les prévisions générales

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Produit/Backend Chetiwa

## Contexte

Chetiwa a besoin de données actuelles, horaires, quotidiennes et de séries de
précipitations pour Weather Brief, Graph et Prévisions. L’intégration actuelle
Open-Meteo est fonctionnelle et isolée derrière le domaine Chetiwa.

## Décision

- Conserver Open-Meteo pour les prévisions générales de la v1.
- Utiliser l’accès gratuit uniquement pour développement et bêta non monétisée.
- Activer une licence/API commerciale avant toute publicité, abonnement ou
  trafic de production monétisé.
- Appeler Open-Meteo uniquement depuis le backend Chetiwa en production.
- Mapper les réponses vers les entités Chetiwa ; aucun modèle fournisseur ne
  traverse la couche domaine.
- Utiliser Rainbow Nowcast pour les alertes pluie immédiates si ses mesures sont
  plus adaptées ; Open-Meteo reste la source des prévisions générales.

L'activation commerciale est reportée par l'ADR-0008 : elle ne doit intervenir
qu'après la bêta et la vérification écrite du droit correspondant au lancement.

## Conséquences

- L’UI et le domaine existants sont conservés.
- Le backend protège la clé, applique cache, quotas et repli stale-if-error.
- L’attribution Open-Meteo et des sources de données doit rester visible.
- Une comparaison régulière avec des observations réelles est nécessaire par
  région de lancement.

## Réévaluation

Réévaluer si la disponibilité, la précision régionale, la licence ou le coût ne
respectent plus les objectifs définis dans les garde-fous business.

## Références

- [Open-Meteo pricing](https://open-meteo.com/en/pricing)
- [Open-Meteo terms](https://open-meteo.com/en/terms)
