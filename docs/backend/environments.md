# Environnements backend Chetiwa

Le backend suit l’ADR-0004 : un monolithe modulaire conteneurisé. La première
production frugale peut fonctionner sur la VM Hetzner existante ; Cloud Run
reste une cible d'évolution lorsque Firestore et l'autoscaling seront activés.

| Environnement | État | Projet cloud | Données et fournisseurs |
|---|---|---|---|
| Local | Exécutable | Aucun | Fixtures, émulateurs et fournisseurs de développement |
| Staging | Profil prêt, projet à provisionner | Projet GCP dédié | Sandbox, clés staging et budgets très bas |
| Production frugale | Profil Hetzner prêt | VM existante | API, Radar et flags sûrs ; alertes distantes désactivées |
| Production avec alertes | Profil Cloud Run prêt, projet à provisionner | Projet GCP dédié | Firestore, FCM, consentement et budgets |

## Règles obligatoires

1. Aucun secret dans Git, l’image Docker ou l’application mobile.
2. `GOOGLE_CLOUD_PROJECT` reste un identifiant explicite hors local. Sur Hetzner,
   il n'entraîne aucun appel Google tant que les deux flags d'alertes sont faux.
3. Staging et production utilisent des comptes de service, budgets et clés
   distincts. Firestore est activé uniquement pour les appareils et alertes ;
   Redis et Cloud CDN restent désactivés par défaut.
4. Cloud Run conserve `min-instances=0` et `max-instances=1` tant qu'aucun
   compteur partagé n'est configuré.
5. Les coordonnées précises ne sont pas journalisées.

## Provisionnement Firestore des alertes

Le code utilise Application Default Credentials et ne contient aucune clé de
service. Après création de la base, exécuter avec un propriétaire du projet :

```sh
backend/deploy/firestore/provision-alert-store.sh \
  PROJECT_ID CLOUD_RUN_SERVICE_ACCOUNT '(default)'
```

Le script active le TTL sur appareils, règles, états et outbox, puis accorde
`roles/datastore.user` et l'envoi FCM au compte du worker. Les règles fournies
refusent tout accès direct depuis les applications mobiles. Le déploiement du
job et de son Scheduler est détaillé dans `smart-rain-alerts-runbook.md`.

## Provisionnement externe restant

La création effective du projet GCP, de la base Firestore, du compte de
facturation, des budgets et de Secret Manager nécessite l’accès propriétaire au
compte Google Cloud. Redis et le CDN restent derrière leurs gates de coût.

## Déploiement API et surveillance

### Production frugale sur Hetzner

Le profil `backend/deploy/hetzner` écoute uniquement sur
`127.0.0.1:8081`. Le tunnel Cloudflare publie
`https://api.ezplatforms.com` vers `http://127.0.0.1:8081`.

Copier `production.env.example` vers `production.env`, générer
`INTERNAL_METRICS_TOKEN`, puis lancer :

```sh
docker compose -f backend/deploy/hetzner/docker-compose.yml up --build -d
curl --fail http://127.0.0.1:8081/healthz
```

Les routes d'alertes distantes échouent volontairement tant que Firestore n'est
pas activé. Graph, météo, recherche, Radar et feature flags restent disponibles.
Le mode `production` exige en plus une clé commerciale Open-Meteo. Tant que
cette clé n'est pas disponible, le conteneur public peut servir uniquement les
tests fermés avec `CHETIWA_ENV=staging` ; il ne constitue pas encore le backend
d'une publication commerciale.

### Production Cloud Run avec alertes

Après avoir créé les secrets `open-meteo-api-key` et
`chetiwa-internal-metrics-token` dans Secret Manager, l'API peut être déployée
avec le workflow manuel GitHub **Deploy backend production** ou localement :

```sh
backend/deploy/cloud-run/deploy-api.sh \
  PROJECT_ID europe-west1 IMAGE_URI \
  chetiwa-api@PROJECT_ID.iam.gserviceaccount.com \
  https://api.chetiwa.app
```

Le workflow utilise Workload Identity Federation, sans JSON de compte de
service. Il doit être protégé par l'environnement GitHub `production` et un
reviewer. Une fois le domaine public actif :

```sh
backend/deploy/cloud-run/provision-api-observability.sh \
  PROJECT_ID api.chetiwa.app \
  'projects/PROJECT_ID/notificationChannels/CHANNEL_ID'
```

La sonde interroge `/healthz` chaque minute depuis trois régions et ouvre une
alerte après deux minutes d'échec. Omettre le troisième argument crée la
politique sans destinataire ; ajouter le canal e-mail avant la bêta publique.
