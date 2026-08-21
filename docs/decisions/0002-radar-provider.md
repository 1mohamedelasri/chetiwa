# ADR-0002 — Rainbow pour le radar de production

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Produit/Backend Chetiwa

## Contexte

Le prototype utilise RainViewer. Son API publique vise les usages personnels,
éducatifs et communautaires limités, sans SLA public adapté à une application
commerciale. Chetiwa a besoin de tuiles radar animées et d’un nowcast cohérent
avec les alertes.

## Décision

- Conserver RainViewer uniquement comme outil de développement temporaire.
- Utiliser Rainbow Tiles pour le radar de production.
- Évaluer Rainbow Nowcast pour le moteur Smart Rain Alerts.
- Obtenir une confirmation contractuelle des droits commerciaux, attribution,
  rétention/cache et limites avant activation production.
- Servir les métadonnées et tokens via le backend Chetiwa.
- Limiter zoom, frames, préchargement et fréquence selon Free/Premium.

L'ADR-0008 reporte ce contrat derrière un gate de coût et de licence : Rainbow
n'est pas une dépense du MVP ni de la bêta locale-first.

## Conséquences

- Le repository radar reste indépendant du fournisseur.
- La palette Chetiwa peut évoluer sans modifier la donnée source.
- Les coûts sont variables au nombre de tuiles ; cache, quotas et remote kill
  switch sont obligatoires.
- Graph et Radar n’utiliseront pas nécessairement la même nature de donnée :
  l’interface doit identifier observation, nowcast et prévision.

## Réévaluation

Réévaluer après la bêta silencieuse des alertes ou si les coûts radar dépassent
20 % du revenu net associé au produit.

## Références

- [Rainbow developer pricing](https://developer.rainbow.ai/)
- [Rainbow Tiles API](https://doc.rainbow.ai/api-ref/tiles/)
- [RainViewer API terms](https://www.rainviewer.com/api.html)
