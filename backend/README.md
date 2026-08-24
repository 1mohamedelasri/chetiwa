# Chetiwa backend

Monolithe modulaire Dart destiné à Cloud Run, conformément à l’ADR-0004. Ce
socle ne contient aucune clé et ne crée aucune ressource cloud payante.

## Démarrage local

```sh
cd backend
dart pub get
CHETIWA_ENV=local dart run bin/server.dart
curl http://localhost:8080/healthz
curl http://localhost:8080/v1
curl 'http://localhost:8080/v1/forecast?latitude=48.8566&longitude=2.3522'
curl 'http://localhost:8080/v1/locations/search?q=Paris&language=fr'
curl 'http://localhost:8080/v1/radar/frames?latitude=48.8566&longitude=2.3522'
curl 'http://localhost:8080/v1/radar/point-nowcast?latitude=48.8566&longitude=2.3522'
curl -X POST http://localhost:8080/v1/radar/sessions \
  -H 'X-Chetiwa-Device-Id: local-device-123' \
  -H 'X-Chetiwa-Radar-Session-Id: local-radar-session-123'
curl -X POST http://localhost:8080/v1/devices \
  -H 'Content-Type: application/json' \
  -H 'X-Chetiwa-Device-Id: local-device-123' \
  -d '{"platform":"ios","locale":"fr","timeZone":"Europe/Paris","notificationsEnabled":false}'
```

Le même service peut être lancé par `docker compose up --build`.

## Profils

- `local` fonctionne sans projet Google Cloud ;
- `staging` et `production` exigent un `GOOGLE_CLOUD_PROJECT` explicite ;
- les exemples sous `deploy/environments` ne contiennent jamais de secret ;
- les clés fournisseurs doivent être injectées depuis Secret Manager.

## API v1 publique

- `GET /v1/forecast?latitude=…&longitude=…`
- `GET /v1/locations/search?q=…&language=fr|en&count=1..12`
- `GET /v1/locations/reverse?latitude=…&longitude=…&language=fr|en`
- `GET /v1/radar/frames?latitude=…&longitude=…`
- `GET /v1/radar/point-nowcast?latitude=…&longitude=…`
- `POST /v1/radar/sessions`
- `GET /v1/radar/tiles/{frame}/{z}/{x}/{y}`
- `GET /internal/metrics` (à protéger par IAM/réseau privé)
- `POST /v1/devices` et `DELETE /v1/devices`
- `GET|POST /v1/alerts`
- `PATCH|DELETE /v1/alerts/{alertId}`

Ces réponses utilisent un contrat Chetiwa indépendant des fournisseurs. Elles
prennent en charge `ETag`/`If-None-Match`, gzip, un cache mémoire LRU borné et un
repli `stale-if-error`. Les coordonnées sont arrondies à trois décimales dans
les clés de cache et ne sont pas journalisées par l’application. Une première
limite locale de 120 requêtes/minute s'applique par identifiant d'installation
`X-Chetiwa-Device-Id`, ou par IP en repli.

Le proxy de tuiles est optionnel. Lorsqu'il est activé, il fournit un cache LRU binaire, `ETag`, `304`,
`stale-if-error`, limites de zoom et budget par tuile. `SHARED_COUNTER_URL`
active le compteur de quotas distribué pour Cloud Run multi-instance ; sans
cette variable, le compteur reste local et aucun service Redis/Firestore n'est
nécessaire. Le contrat complet et le runbook sont
décrits dans
[`docs/backend/api-v1.md`](../docs/backend/api-v1.md).
Voir aussi [`cdn-shared-backend-runbook.md`](../docs/backend/cdn-shared-backend-runbook.md).

Le déploiement de l'API est reproductible avec
`deploy/cloud-run/deploy-api.sh`. Il conserve une seule instance maximale tant
qu'aucun compteur partagé n'est configuré, démarre Premium, publicités et
alertes distantes désactivés, puis vérifie `/healthz`. La sonde publique et sa
politique d'alerte sont provisionnées séparément par
`deploy/cloud-run/provision-api-observability.sh` : le dépôt ne crée donc
aucune ressource cloud automatiquement.

Les routes device/alertes sont décrites dans
[`docs/backend/device-alert-api.md`](../docs/backend/device-alert-api.md). Elles
utilisent un store mémoire uniquement en profil `local`. Le serveur injecte
automatiquement Firestore en staging/production avec les Application Default
Credentials du compte de service Cloud Run. Le déploiement doit avoir exécuté
`deploy/firestore/provision-alert-store.sh` et reçu `roles/datastore.user`.
Le job `bin/alert_worker.dart` exécute N0.4–N0.8 : mutualisation géographique,
transition pluie, quiet hours du téléphone, outbox dédupliquée et envoi FCM
HTTP v1. Il démarre sans envoi en shadow mode, lit son kill switch dans
Firestore et écrit uniquement des métriques agrégées. Le service privé
`bin/alert_budget_guard.dart` traite les notifications Cloud Billing et coupe
le moteur à 50 €. Leur activation est documentée dans
[`smart-rain-alerts-runbook.md`](../docs/backend/smart-rain-alerts-runbook.md).

## Configuration fournisseur

| Variable | Usage |
| --- | --- |
| `OPEN_METEO_API_KEY` | clé commerciale prévisions/geocoding en production |
| `FIRESTORE_DATABASE_ID` | base Firestore des appareils/alertes, `(default)` par défaut |
| `OPEN_METEO_FORECAST_URL` | remplacement contrôlé de l’URL de prévisions |
| `OPEN_METEO_METEOFRANCE_URL` | route AROME 15 min pour la France métropolitaine |
| `OPEN_METEO_GEOCODING_URL` | remplacement contrôlé de l’URL de recherche |
| `RADAR_PROVIDER` | type explicite : `librewxr`, `rainviewer` (dev) ou `configured` |
| `RADAR_QUOTA_ENFORCED` | `false` en bêta : mesure les ouvertures sans bloquer le Radar |
| `RADAR_METADATA_URL` | métadonnées radar ; LibreWXR est le défaut bêta |
| `ARCGIS_API_KEY` | reverse geocoding ArcGIS, si cette option est retenue |
| `REVERSE_GEOCODING_URL` | endpoint de reverse geocoding |
| `RADAR_TILE_URL_TEMPLATE` | source des tuiles avec `{frame}/{z}/{x}/{y}` ; LibreWXR est le défaut bêta |
| `PUBLIC_BASE_URL` | URL HTTPS publique du backend, obligatoire avec le radar en production |
| `SHARED_COUNTER_URL` | compteur atomique Redis/Firestore partagé |
| `MONTHLY_BUDGET_CENTS` | plafond mensuel des coûts origine |
| `RADAR_TILE_COST_CENTS` | coût estimé par tuile origine (0 pour LibreWXR bêta) |
| `GLOBAL_KILL_SWITCH` | désactivation immédiate du Radar, des tuiles et du worker d’alertes |
| `PREMIUM_ENABLED` | rend l’offre Chetiwa+ visible pour les installations éligibles |
| `PREMIUM_ROLLOUT_PERCENT` | déploiement stable de Chetiwa+ par installation, de `0` à `100` |
| `ADS_ENABLED` | active les emplacements publicitaires pour les non-Premium |
| `RAIN_ALERTS_ENABLED` | active explicitement le worker, `false` par défaut |
| `RAIN_ALERTS_SEND_ENABLED` | autorise FCM ; `false` conserve le shadow mode par défaut |
| `RAIN_ALERT_CELL_SIZE_DEGREES` | taille stable des cellules mutualisées, `0.05` par défaut |
| `RAIN_ALERT_MAX_CONCURRENT_CELLS` | concurrence fournisseur bornée, `8` par défaut |
| `RAIN_ALERT_SOFT_BUDGET_CENTS` | seuil d’avertissement, `2500` par défaut |
| `RAIN_ALERT_HARD_BUDGET_CENTS` | coupure persistante du moteur, `5000` par défaut |
| `RAIN_ALERT_BUDGET_CURRENCY` | devise attendue du message Cloud Billing, `EUR` par défaut |

Les URLs externes doivent être HTTPS hors profil local. Le service refuse
RainViewer en profil `production`, mais accepte LibreWXR, dont l'API publique
est attribuée dans l'application. Open-Meteo exige toujours une clé commerciale
en production. Le proxy Cloud Run est le seul point d'accès mobile : il met en
cache les métadonnées et tuiles, applique les quotas et permet un remplacement
du fournisseur sans mise à jour de l'application.

## Vérification

```sh
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```
