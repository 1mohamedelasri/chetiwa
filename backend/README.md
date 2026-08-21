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
- `POST /v1/devices` et `DELETE /v1/devices`
- `GET|POST /v1/alerts`
- `PATCH|DELETE /v1/alerts/{alertId}`

Ces réponses utilisent un contrat Chetiwa indépendant des fournisseurs. Elles
prennent en charge `ETag`/`If-None-Match`, gzip, un cache mémoire LRU borné et un
repli `stale-if-error`. Les coordonnées sont arrondies à trois décimales dans
les clés de cache et ne sont pas journalisées par l’application. Une première
limite locale de 120 requêtes/minute s'applique par identifiant d'installation
`X-Chetiwa-Device-Id`, ou par IP en repli.

Le cache et le rate limiting mémoire sont des premiers garde-fous locaux à
chaque instance. Un contrôle distribué reste nécessaire avant le trafic de
production. Le contrat complet est décrit dans
[`docs/backend/api-v1.md`](../docs/backend/api-v1.md).

Les routes device/alertes sont décrites dans
[`docs/backend/device-alert-api.md`](../docs/backend/device-alert-api.md). Elles
utilisent un store mémoire uniquement en profil `local`. Hors local, elles
refusent de démarrer une fausse persistance et répondent `503` tant que le store
Firestore n’est pas injecté.

## Configuration fournisseur

| Variable | Usage |
| --- | --- |
| `OPEN_METEO_API_KEY` | clé commerciale prévisions/geocoding en production |
| `OPEN_METEO_FORECAST_URL` | remplacement contrôlé de l’URL de prévisions |
| `OPEN_METEO_GEOCODING_URL` | remplacement contrôlé de l’URL de recherche |
| `RADAR_METADATA_URL` | métadonnées du fournisseur radar autorisé |
| `ARCGIS_API_KEY` | reverse geocoding ArcGIS, si cette option est retenue |
| `REVERSE_GEOCODING_URL` | endpoint de reverse geocoding |

Les URLs externes doivent être HTTPS hors profil local. Le service refuse
RainViewer et Open-Meteo sans clé commerciale en profil `production` afin
d’éviter une publication accidentelle hors licence.

## Vérification

```sh
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```
