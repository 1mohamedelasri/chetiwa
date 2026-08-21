# ADR-0004 — Monolithe modulaire sur Cloud Run/Firebase

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Backend/Operations Chetiwa

## Contexte

Chetiwa doit protéger les clés fournisseurs, centraliser le cache, envoyer les
alertes et valider les droits Premium. Un système distribué augmenterait trop tôt
le coût et la charge opérationnelle.

## Décision

- Construire une seule API modulaire conteneurisée sur Cloud Run, région UE.
- Utiliser le billing par requête avec `min-instances=0` au lancement.
- Commencer avec `max-instances=3`, puis augmenter seulement après mesure.
- Utiliser Firebase Cloud Messaging pour les notifications.
- Utiliser Firestore pour installations, règles d’alerte et entitlements MVP.
- Utiliser Secret Manager pour toutes les clés.
- Utiliser Firebase Remote Config pour les feature flags publics et une
  configuration backend sécurisée pour les kill switches critiques.
- Ne pas créer de compte utilisateur obligatoire en v1 ; utiliser un identifiant
  d’installation aléatoire et révocable.
- Séparer strictement projets local, staging et production.

## Modules du monolithe

- Forecast et geocoding proxy.
- Radar metadata/token proxy.
- Cache et quotas.
- Devices et notifications.
- Alert rules.
- Subscription entitlements.
- Feature flags et health endpoints.

## Garde-fous

- Budget Cloud avec alertes 50/75/90/100 %.
- Rate limits et quotas par installation/IP.
- Coordonnées exactes absentes des logs.
- Sauvegarde/export Firestore et test de restauration.
- API versionnée et idempotence pour devices, achats et alertes.

## Réévaluation

Réévaluer base de données et hébergement uniquement si charge, requêtes complexes,
coûts ou portabilité le justifient. Le conteneur doit rester exécutable hors
Cloud Run.

## Références

- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Cloud Run maximum instances](https://cloud.google.com/run/docs/configuring/max-instances)
- [Firebase pricing](https://firebase.google.com/pricing)

