# Runbook — CDN, quotas et continuité Radar

## Architecture

Le mobile demande les tuiles via :

Mode économique par défaut : `client → cache mobile → fournisseur`.

Mode proxy optionnel, uniquement si la licence l'impose :
`client → Cloud Run /v1/radar/tiles/{frame}/{z}/{x}/{y} → fournisseur`.

Cloud CDN est un accélérateur optionnel, pas une dépendance obligatoire.

La clé CDN est le chemin normalisé `frame/z/x/y`. Les coordonnées utilisateur ne
font jamais partie de la clé. Le proxy renvoie `ETag`, `Cache-Control` avec six
heures de fraîcheur et deux jours de `stale-if-error`.

Le cache mémoire LRU du proxy est limité à 2 048 entrées et 128 Mo par instance.
Si Cloud CDN est activé plus tard, il partage les tuiles entre instances ; il ne
doit être provisionné qu'après mesure du taux de hit mobile et du coût d'origine.

## Déploiement multi-instance

Avant de passer `max-instances` au-dessus de 1 :

1. Déployer un service de compteur atomique partagé Redis ou Firestore.
2. Exposer son endpoint interne `POST /increment` avec authentification réseau.
3. Définir `SHARED_COUNTER_URL` dans le profil Cloud Run.
4. Vérifier que deux instances incrémentent la même clé mensuelle.
5. Tester le dépassement Free et Premium en staging.

Sans `SHARED_COUNTER_URL`, le compteur reste local à l’instance. C'est le mode
recommandé pour la bêta et impose `max-instances=1`.

## Budget et seuils

`MONTHLY_BUDGET_CENTS` est le plafond mensuel. Chaque tuile origine consomme
`RADAR_TILE_COST_CENTS`. Les alertes sont produites une fois à 50 %, 75 % et
90 %. À 100 %, le service renvoie `503 budget_kill_switch` si le kill switch
budget est actif. `GLOBAL_KILL_SWITCH=true` désactive immédiatement le Radar et
les tuiles.

Les métriques sont disponibles sur la route interne `/internal/metrics` :
latence moyenne, erreurs, fraîcheur, cache hit rate, octets et alertes budget.
Cette route doit être protégée par IAM ou par le réseau privé Cloud Run avant
exposition publique.

## Incident fournisseur Radar

1. Passer `GLOBAL_KILL_SWITCH=true` si le fournisseur renvoie des erreurs ou si
   le quota est proche du plafond.
2. Vérifier `x-cache` et servir les réponses `STALE` tant qu'elles restent dans
   la fenêtre de deux jours.
3. Si le fournisseur ne revient pas, basculer le mobile sur son fallback visuel
   et fixture déjà existant.
4. Remplacer `RADAR_TILE_URL_TEMPLATE` par le fournisseur licencié de secours.
5. Réinitialiser le kill switch après test staging et vérifier l'attribution.
6. Documenter l'heure, le fournisseur, le volume de tuiles et le coût dans le
   registre fournisseur.

## Incident quotas / compteur partagé

Si le compteur partagé est indisponible, ne pas le remplacer silencieusement par
un compteur local en production. Garder une instance Cloud Run, activer le kill
switch si nécessaire, puis restaurer le service partagé avant de rouvrir le
trafic.
