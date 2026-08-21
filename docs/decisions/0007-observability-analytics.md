# ADR-0007 — Firebase pour observabilité et analytics minimaux

- Statut : Partiellement adopté — Firebase Analytics opt-in uniquement
- Date : 2026-08-20
- Propriétaire : Produit/Operations/Privacy Chetiwa

## Contexte

Le lancement devra mesurer stabilité, performance, usage essentiel et économie
sans collecter inutilement une historique de localisation personnelle. Le MVP
local-first n'a toutefois pas besoin d'un SDK cloud d'observabilité : les tests,
feedback de bêta et mesures locales minimales passent en premier.

## Décision

- Utiliser Firebase Analytics pour les événements produit minimaux, uniquement
  après un choix explicite et réversible dans l'application.
- Ne pas activer Crashlytics, Performance Monitoring, Remote Config, Firestore,
  Cloud Functions, Cloud Storage, FCM ou une base de données sans une nouvelle
  décision, budget et gate de coût.
- Ne jamais envoyer coordonnées exactes, requêtes de recherche, noms de lieux
  personnels ou contenu de notification dans les événements analytics/crash.
- Utiliser des catégories larges de pays/zone seulement si nécessaires et
  compatibles avec le consentement.
- Désactiver la collecte avant consentement lorsque la réglementation ou la
  configuration choisie le requiert.

## Événements v1 autorisés et effectivement implémentés

- `weather_tab_selected` avec `tab` graph/radar/forecast.
- `location_search_requested`, sans texte de recherche.
- `location_selected` avec `source` selected/precise/reducedAccuracy/
  lastKnownPosition, sans ville ni coordonnées.
- `rain_alert_preference_changed` avec `enabled` true/false.

Les événements d'ouverture, de chargement, de paywall, d'achat, de publicité ou
d'erreur ne sont pas ajoutés tant que leur finalité, leur base légale et le
produit concerné ne sont pas validés.

Tout nouvel événement doit avoir une finalité, un propriétaire et une durée de
rétention documentés avant implémentation.

## Référence

- [Firebase pricing and no-cost products](https://firebase.google.com/pricing)
