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
`nowcast`, ainsi qu’un modèle d’URL de tuile. Cette chronologie est globale et
n’écho pas les coordonnées de la requête ; les données au point restent sur
`/v1/radar/point-nowcast`. Politique : fraîche 2 minutes,
repli maximal 30 minutes. RainViewer est accepté uniquement en développement ;
le profil production le refuse tant qu’un fournisseur licencié n’est pas
configuré.

### `GET /v1/radar/point-nowcast`

Paramètres requis : `latitude`, `longitude`.

Retourne les six échantillons de pluie au point LibreWXR pour les 60 prochaines
minutes, avec `time`, `rainRateMmPerHour`, `source` et `coverage`. Le mobile les
fusionne uniquement avec les frames `nowcast` du graphe. Une panne ou un timeout
de cette route ne bloque ni la carte ni le graphe, qui conserve alors les valeurs
Open-Meteo. Politique : fraîche 2 minutes, repli maximal 30 minutes, avec une clé
arrondie à environ 100 m. Cette lecture technique ne consomme pas le quota de
sessions Radar.

### `POST /v1/radar/sessions`

Enregistre une ouverture réellement déclenchée par l'utilisateur. Les en-têtes
`X-Chetiwa-Device-Id` et `X-Chetiwa-Radar-Session-Id` sont obligatoires ; le
second rend les retries idempotents. `X-Chetiwa-Plan: free|premium` sélectionne
la limite annoncée par le client. La réponse contient `allowed`, `enforced`,
`overLimit`, `used`, `limit`, `remaining` et `resetAt`.

En bêta, `RADAR_QUOTA_ENFORCED=false` compte les ouvertures mais conserve
`allowed=true`, même au-delà de la limite. Le plan client ne constitue pas une
preuve d'achat : avant d'activer le blocage, il faut valider les achats côté
serveur et utiliser un compteur partagé. Les rafraîchissements de
`GET /v1/radar/frames`, le point-nowcast et les tuiles ne consomment jamais une
session.

### `GET /v1/radar/tiles/{frame}/{z}/{x}/{y}`

Proxy binaire pour une tuile Radar. `frame` est un identifiant opaque validé par
le backend ; les coordonnées XYZ sont bornées à `z=0..12`. La réponse renvoie
`ETag`, `304`, `X-Cache`, `Cache-Control: max-age=21600, stale-if-error=172800`
et peut être placée derrière un CDN HTTP avec la clé `frame/z/x/y`.

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

## Quota Radar et kill switch

`POST /v1/radar/sessions` applique le compteur mensuel par installation : 20
ouvertures Free et 200 Chetiwa+ par défaut. `RADAR_ENABLED=false` renvoie
`503 radar_disabled`. Les compteurs restent en mémoire tant qu'une seule
instance est utilisée. Avant plusieurs instances Cloud Run, ils doivent être
remplacés par un compteur partagé et reliés aux alertes 50/75/90 %.

`SHARED_COUNTER_URL` active un compteur atomique externe pour que les quotas
restent cohérents entre instances Cloud Run. Sans cette variable, le compteur
reste local et le déploiement doit rester mono-instance.

## Métriques et budget

`GET /internal/metrics` expose les compteurs internes de latence, erreurs,
fraîcheur, cache hit rate, octets et tuiles. La route doit rester protégée par
IAM ou réseau privé. `MONTHLY_BUDGET_CENTS` et `RADAR_TILE_COST_CENTS` contrôlent
le budget origine ; les seuils 50/75/90 % sont enregistrés et le seuil 100 %
renvoie `503 budget_kill_switch`. `GLOBAL_KILL_SWITCH=true` désactive
immédiatement les routes Radar.

## Cache mobile des tuiles Radar

Le client utilise le cache mémoire d'images de `flutter_map` et son cache disque
natifs, configuré à 64 Mo avec une fraîcheur maximale de 6 heures et réduction
LRU. Les requêtes concurrentes sont consolidées par `ImageProvider` et les
requêtes devenues obsolètes sont annulées. Après 600 ms sans mouvement, la couche
Radar précharge au maximum une frame, huit tuiles et deux requêtes simultanées,
avec un timeout de 8 secondes. L'autoplay est désactivé au démarrage et le zoom
est limité à 10. Les métriques locales sont anonymes : taux de hit, octets,
tuiles téléchargées et tuiles uniques par session.
