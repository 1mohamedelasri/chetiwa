# ADR-0003 — Google Maps satellite hybride pour tous

- Statut : Remplace la décision du 2026-08-20
- Date : 2026-08-25
- Propriétaire : Produit/Mobile Chetiwa

## Contexte

Le fond doit rester fluide pendant le déplacement et l’animation LibreWXR sur
Android et iOS. L’ancien assemblage Flutter/OpenFreeMap/Esri multipliait les
réseaux, moteurs, licences, caches et chemins de dégradation.

## Décision

- Utiliser `google_maps_flutter`, donc les SDK Google Maps natifs Android/iOS.
- Afficher `MapType.hybrid` par défaut dans Radar et laisser `MapType.normal`
  sélectionnable, sans entitlement ni feature flag.
- Conserver LibreWXR comme `TileOverlay` distinct, validé et mis en cache par
  Chetiwa (128 Mo disque, 16 Mo mémoire, quatre téléchargements simultanés).
- Utiliser une clé par plateforme, restreinte à l’API et à l’application.
- Ne pas configurer de Map ID afin de rester sur le SKU SDK mobile standard.
- Laisser visibles le logo Google et les attributions natives ; le widget carte
  s’arrête au-dessus de la timeline Radar.

## Conséquences

- Un seul moteur et un seul fournisseur de fond sur les deux plateformes.
- Le satellite devient une fonction essentielle gratuite, pas un argument
  Premium.
- La facturation Google Cloud reste requise même lorsque le SKU mobile est dans
  son régime gratuit ; quotas, alertes et restrictions de clés restent suivis.
- Une panne Google Maps ne doit pas empêcher Graph/Prévisions de fonctionner.

## Réévaluation

Réévaluer si Google modifie les conditions/prix, si la télémétrie montre des
erreurs de rendu, ou si un besoin hors-ligne impose un fond auto-hébergé.

## Références

- [Maps SDK for Android](https://developers.google.com/maps/documentation/android-sdk/overview)
- [Maps SDK for iOS](https://developers.google.com/maps/documentation/ios-sdk/overview)
- [Google Maps Platform terms](https://cloud.google.com/maps-platform/terms)
