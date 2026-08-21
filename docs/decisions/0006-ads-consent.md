# ADR-0006 — AdMob et UMP derrière des repositories

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Produit/Privacy Chetiwa

## Contexte

Chetiwa Free doit pouvoir générer un revenu sans empêcher la lecture météo. Les
règles de consentement varient selon région, âge, personnalisation et plateforme.

## Décision

- Utiliser Google Mobile Ads/AdMob pour le MVP.
- Utiliser Google UMP comme CMP initiale, sous validation des exigences légales et
  stores des pays de lancement.
- Isoler les SDK derrière `AdsRepository` et `ConsentRepository`.
- Ne demander une publicité que si `canShowAds && canRequestAds`.
- Utiliser uniquement le slot adaptatif réservé au-dessus de la navigation.
- Ne jamais afficher d’interstitiel au démarrage ni pendant une interaction météo.
- Désactiver SDK, requêtes et slot pour Chetiwa+.
- Permettre de revoir les choix de confidentialité depuis Settings.

## Garde-fous

- Publicités de test obligatoires hors production.
- ATT iOS uniquement si le comportement réel nécessite du tracking inter-app.
- Feature flag global pour couper la publicité.
- Mesurer revenu net et impact sur rétention avant d’ajouter un format.

## Référence

- [Google UMP for Flutter](https://developers.google.com/admob/flutter/privacy)

