# ADR-0007 — Firebase pour observabilité et analytics minimaux

- Statut : Reporté pour le MVP par ADR-0008
- Date : 2026-08-20
- Propriétaire : Produit/Operations/Privacy Chetiwa

## Contexte

Le lancement devra mesurer stabilité, performance, usage essentiel et économie
sans collecter inutilement une historique de localisation personnelle. Le MVP
local-first n'a toutefois pas besoin d'un SDK cloud d'observabilité : les tests,
feedback de bêta et mesures locales minimales passent en premier.

## Décision

- Après le Gate de l'ADR-0008, utiliser Firebase Crashlytics et Performance
  Monitoring pour la stabilité.
- Utiliser Firebase Analytics pour les événements produit minimaux.
- Utiliser Remote Config pour rollout et flags non secrets.
- Ne jamais envoyer coordonnées exactes, requêtes de recherche, noms de lieux
  personnels ou contenu de notification dans les événements analytics/crash.
- Utiliser des catégories larges de pays/zone seulement si nécessaires et
  compatibles avec le consentement.
- Désactiver la collecte avant consentement lorsque la réglementation ou la
  configuration choisie le requiert.

## Événements v1 autorisés

- `app_opened`, `forecast_loaded`, `forecast_failed`.
- `graph_viewed`, `radar_viewed`, `forecast_viewed`.
- `location_method_selected` avec valeur search/gps/map, sans texte ni coordonnées.
- `alert_cta_clicked`, `alert_enabled`, `alert_disabled`.
- `paywall_viewed`, `subscription_started`, `subscription_purchased`.
- `ad_impression` via l’intégration publicitaire prévue.

Tout nouvel événement doit avoir une finalité, un propriétaire et une durée de
rétention documentés avant implémentation.

## Référence

- [Firebase pricing and no-cost products](https://firebase.google.com/pricing)
