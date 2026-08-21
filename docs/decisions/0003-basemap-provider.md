# ADR-0003 — OpenFreeMap par défaut, Esri satellite Premium

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Produit/Mobile Chetiwa

## Contexte

Le fond de carte donne le contexte géographique au radar, mais ne constitue pas
la donnée météo. Le produit doit éviter une facture satellite avant de générer
des revenus.

## Décision

- Utiliser MapLibre avec OpenFreeMap comme fond standard clair/sombre de la v1.
- Afficher les attributions OpenFreeMap/OpenMapTiles/OpenStreetMap.
- Ne pas dépendre d’un SLA OpenFreeMap : prévoir cache et fond minimal de repli.
- Désactiver Esri satellite dans Chetiwa Free.
- Proposer Esri satellite plus tard dans Chetiwa+ uniquement, après configuration
  officielle du token, des attributions, du quota et du budget.
- Ne pas utiliser les serveurs publics `tile.openstreetmap.org` comme backend de
  production de l’application.

## Conséquences

- Le lancement peut fonctionner sans coût variable de fond de carte standard.
- Le rendu ne sera pas une photographie satellite par défaut.
- L’option satellite ne sera activée que si les revenus Premium couvrent sa
  consommation avec marge.

## Réévaluation

Réévaluer OpenFreeMap si sa disponibilité en bêta est insuffisante. Dans ce cas,
self-host PMTiles ou sélectionner un fournisseur avec SLA et budget explicite.

## Références

- [OpenFreeMap](https://openfreemap.org/)
- [OpenFreeMap terms](https://openfreemap.org/tos/)
- [Esri static basemap pricing](https://developers.arcgis.com/rest/static-basemap-tiles/)

