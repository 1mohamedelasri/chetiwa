# API Chetiwa v1 — contrats publics météo et localisation

Ce document fixe les premiers contrats du proxy Chetiwa. Le mobile ne doit pas
dépendre des noms de champs Open-Meteo, RainViewer, Rainbow ou ArcGIS : les
adaptateurs serveur les traduisent vers ces réponses stables.

## Enveloppe et erreurs

Une réponse réussie contient :

```json
{
  "data": {},
  "meta": { "generatedAt": "2026-08-20T18:00:00.000Z" }
}
```

Une erreur contient un code stable sans détail secret :

```json
{
  "error": {
    "code": "invalid_latitude",
    "message": "latitude must be between -90.0 and 90.0"
  }
}
```

Toutes les coordonnées entrantes sont validées. Les langues supportées sont
`fr` et `en`. Les clés de cache arrondissent les coordonnées à environ 100 m et
aucune route n’écrit les coordonnées dans les logs applicatifs.

## Routes disponibles

### `GET /v1/forecast`

Paramètres requis : `latitude`, `longitude`.

Retourne le lieu et son fuseau, les conditions actuelles, la pluie par pas de
15 minutes, les heures et les jours. Les instants sont en ISO-8601 UTC ; le
mobile les affiche dans `location.timeZone`.

Politique : fraîche 5 minutes, repli périmé maximal 6 heures.

### `GET /v1/locations/search`

Paramètres : `q` requis (2–120 caractères), `language` (`fr` par défaut),
`count` (8 par défaut, maximum 12).

Retourne une liste de lieux normalisés avec nom, pays, région, coordonnées et
fuseau. Politique : fraîche 24 heures, repli maximal 7 jours.

### `GET /v1/locations/reverse`

Paramètres requis : `latitude`, `longitude`; `language` est optionnel.

Retourne un lieu normalisé. L’implémentation actuelle nécessite une clé ArcGIS
serveur. Politique : fraîche 24 heures, repli maximal 7 jours.

### `GET /v1/radar/frames`

Paramètres requis : `latitude`, `longitude`.

Retourne des frames ordonnées, explicitement marquées `observation` ou
`nowcast`, ainsi qu’un modèle d’URL de tuile. Politique : fraîche 2 minutes,
repli maximal 30 minutes. RainViewer est accepté uniquement en développement ;
le profil production le refuse tant qu’un fournisseur licencié n’est pas
configuré.

## Cache HTTP

Les routes renvoient `ETag`, `Cache-Control` et `X-Cache` (`MISS`, `HIT` ou
`STALE`). Un `If-None-Match` valide produit `304 Not Modified`. Les grandes
réponses JSON utilisent gzip lorsque le client l'accepte. En cas de panne
fournisseur, une entrée encore dans sa fenêtre de secours est renvoyée avec
`Warning: 110` plutôt qu’un écran vide.

Une limite locale par instance protège immédiatement l’API : 120 requêtes par
minute et par `X-Chetiwa-Device-Id` valide, avec repli par IP. Un dépassement
renvoie `429`, `Retry-After` et les en-têtes `X-RateLimit-*`. L’identifiant est
un identifiant aléatoire d’installation, jamais un identifiant publicitaire.

Le cache LRU et le rate limiting actuels sont volontairement en mémoire. Avant
Gate 2, il faut ajouter contrôle partagé multi-instance, métriques de hit rate et
quotas pilotables par environnement.
