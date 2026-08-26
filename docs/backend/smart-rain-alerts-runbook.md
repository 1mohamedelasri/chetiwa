# Smart Rain Alerts — activation APNs, Firestore, worker et budget

Le dépôt contient N0.1 à N0.8, mais il ne peut pas créer une clé privée Apple
ni choisir à la place du propriétaire l'emplacement irréversible de Firestore.
Ne jamais ajouter une clé `.p8`, un JSON de compte de service ou un token push
au dépôt.

## 1. Obtenir et téléverser la clé APNs

Prérequis : rôle **Account Holder** ou **Admin** dans Apple Developer et compte
Apple Developer actif.

1. Ouvrir <https://developer.apple.com/account/resources/authkeys/list>.
2. Cliquer sur `+`, nommer la clé `Chetiwa APNs` et activer
   **Apple Push Notification service (APNs)**.
3. Choisir une clé adaptée à l'app Chetiwa. Une clé team-scoped couvre les apps
   de l'équipe ; conserver le périmètre le plus petit compatible avec le compte.
4. Télécharger le fichier `AuthKey_<KEY_ID>.p8`. Apple ne permet qu'un seul
   téléchargement : le conserver dans un gestionnaire de secrets hors du dépôt.
5. Noter le **Key ID** affiché sur la clé et le **Team ID** de la page Membership.
6. Ouvrir <https://console.firebase.google.com/>, projet `chetiwa`, puis
   **Paramètres du projet → Cloud Messaging → configuration de l'app iOS →
   clé d'authentification APNs → Importer**.
7. Sélectionner le `.p8`, saisir le Key ID et le Team ID si Firebase le demande,
   puis importer. Une clé APNs d'authentification peut servir aux environnements
   de développement et de production selon sa configuration Apple.

Ensuite, installer une build signée sur un vrai iPhone, accepter les
notifications et envoyer un message de test depuis Firebase Cloud Messaging.
Valider premier plan, arrière-plan et app retirée des apps récentes. Le
**Forcer l'arrêt** Android reste un cas système différent.

Documentation officielle :

- <https://developer.apple.com/help/account/keys/create-a-private-key>
- <https://firebase.google.com/docs/cloud-messaging/ios/get-started>

## 2. Créer et provisionner Firestore

1. Ouvrir le projet Firebase `chetiwa` puis **Databases & Storage → Firestore →
   Create database**.
2. Choisir **Standard edition**, base `(default)` et **Production mode**. Ce
   mode refuse les SDK mobiles ; le backend Cloud Run passe par IAM.
3. Choisir la même région que Cloud Run, ou la région européenne décidée pour
   le projet. L'emplacement de la base ne se change pas ensuite : le vérifier
   avant de confirmer.
4. Réauthentifier les CLI locales :

   ```sh
   gcloud auth login
   gcloud auth application-default login
   firebase login --reauth
   ```

5. Provisionner règles, IAM et TTL :

   ```sh
   cd backend
   ./deploy/firestore/provision-alert-store.sh \
     chetiwa \
     chetiwa-alert-worker@chetiwa.iam.gserviceaccount.com
   ```

Le script vérifie que la base existe, active les TTL pour appareils, règles,
états et outbox, accorde l'accès Firestore/FCM au worker et déploie les règles
deny-all côté mobile. Il ne choisit et ne crée pas automatiquement la région.

Documentation officielle :

- <https://firebase.google.com/docs/firestore/quickstart>
- <https://firebase.google.com/docs/firestore/manage-databases>
- <https://cloud.google.com/firestore/docs/ttl>

## 3. Déployer le job N0.4–N0.6

Créer deux comptes de service séparés, puis construire l'image backend :

```sh
gcloud iam service-accounts create chetiwa-alert-worker --project=chetiwa
gcloud iam service-accounts create chetiwa-alert-scheduler --project=chetiwa
gcloud builds submit backend \
  --project=chetiwa \
  --tag=europe-west1-docker.pkg.dev/chetiwa/chetiwa/chetiwa-backend:alerts-n06
```

Copier `backend/deploy/alerts/staging.env.yaml.example`, remplacer les valeurs,
laisser `RAIN_ALERTS_ENABLED: "false"` pendant le provisionnement, puis lancer :

```sh
backend/deploy/alerts/provision-alert-worker.sh \
  chetiwa \
  europe-west1 \
  europe-west1-docker.pkg.dev/chetiwa/chetiwa/chetiwa-backend:alerts-n06 \
  chetiwa-alert-worker@chetiwa.iam.gserviceaccount.com \
  chetiwa-alert-scheduler@chetiwa.iam.gserviceaccount.com \
  /chemin/absolu/chetiwa-alerts-staging.yaml
```

Le script déploie un Cloud Run Job mono-tâche et un Cloud Scheduler toutes les
5 minutes. Le lease Firestore protège aussi contre la livraison *at least once*
de Scheduler. Pour le premier essai réel, activer uniquement le staging,
exécuter manuellement le job et inspecter sa ligne JSON de synthèse :

```sh
gcloud run jobs execute chetiwa-rain-alerts \
  --project=chetiwa --region=europe-west1 --wait
```

Les secrets fournisseurs éventuels doivent être liés depuis Secret Manager au
job Cloud Run ; ne jamais les copier dans le fichier YAML.

### Polling adaptatif sans nouveau service

Le Scheduler continue de réveiller le job toutes les cinq minutes, mais le job
ne contacte pas aveuglément le fournisseur pour chaque cellule. Il lit le petit
document Firestore `alertCellSchedules/{cellKey}` et saute les cellules qui ne
sont pas encore dues :

- pluie dans la fenêtre d'alerte : nouvelle vérification dans 5 minutes ;
- pluie plus éloignée : nouvelle vérification dans 10 à 30 minutes ;
- aucune pluie sur un horizon d'au moins 2 h : sommeil de 1 h ;
- aucune pluie sur un horizon d'au moins 4 h : sommeil de 2 h ;
- horizon LibreWXR limité à environ 60 minutes : contrôle prudent toutes les
  15 minutes ;
- panne fournisseur : retry après 15 minutes.

Le moteur ne crée une cellule que pour une règle active appartenant à un
appareil valide avec notifications activées. Un changement de lieu remplace la
règle principale ; l'ancienne cellule n'est donc plus interrogée dès le passage
suivant. Les calendriers orphelins expirent automatiquement après sept jours via
le TTL Firestore. Ils ne contiennent aucun token, identifiant d'appareil ni
coordonnée exacte d'utilisateur.

Ne pas ajouter Redis, une seconde base, un Scheduler par ville ou du batching
Open-Meteo pour cette V1. Le batching diminue le nombre de connexions HTTP mais
pas les unités facturées. Il n'existe pas non plus de coupure nocturne globale :
les heures silencieuses choisies par chaque utilisateur restent autoritaires.

### Estimation Firestore par DAU

Le DAU n'est pas l'unité de coût réelle. Les deux facteurs dominants sont le
nombre d'utilisateurs ayant activé les alertes et le nombre de cellules de
`0,05°` distinctes. Le tableau ci-dessous est un budget prudent, pas une
garantie de facture. Hypothèses : 25 % d'opt-in, trois synchronisations mobiles
par jour, dix abonnés en moyenne par cellule, horizon LibreWXR court contrôlé au
maximum toutes les 15 minutes, 30 jours et tarifs Firestore Standard de
référence en USD (`$0.03/100k` lectures et `$0.09/100k` écritures après le quota
gratuit quotidien).

| DAU | Alertes actives | Lectures/jour | Écritures/jour | Firestore/mois estimé | Cas dispersé : 1 cellule/utilisateur |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 000 | 250 | 77 400 | 3 900 | environ $0.25 | environ $0.60 |
| 10 000 | 2 500 | 774 000 | 39 100 | environ $7 | environ $15 |
| 40 000 | 10 000 | 3 096 000 | 156 500 | environ $31 | environ $62 |
| 50 000 | 12 500 | 3 870 000 | 195 600 | environ $39 | environ $78 |

Le stockage reste normalement sous le GiB gratuit jusqu'à ces volumes et les
suppressions/TTL restent négligeables. À 50 000 DAU mais seulement 10 % d'opt-in,
le même modèle donne environ `$15/mois`. Vérifier chaque semaine le ratio réel
`alertes actives / DAU`, le nombre d'abonnés par cellule et les opérations dans
Firestore Usage ; ne jamais extrapoler uniquement depuis le DAU.

Cette estimation montre que le garde-budget de 25 EUR peut être atteint avant
50 000 DAU. Avant ce palier, optimiser le worker pour interroger d'abord la
prévision de la cellule et ne charger les documents abonnés que lorsqu'un
épisode pluvieux doit être évalué ou lors d'un audit périodique d'appartenance.
Ne pas introduire Redis pour résoudre ce point : il déplacerait le coût sans
supprimer les lectures inutiles.

Coûts séparés de Firestore : FCM est gratuit ; un seul Cloud Scheduler entre
dans les trois jobs gratuits ; le Cloud Run Job toutes les cinq minutes coûte
environ `$3/mois` au minimum avec 1 vCPU/512 MiB à cause de la facturation
minimum d'une minute par exécution, puis augmente avec sa durée réelle ; et la
licence commerciale Open-Meteo reste un abonnement distinct. Mesurer Cloud Run
en shadow mode avant d'en déduire un coût à 10k ou 50k DAU.

## 4. Valider le shadow mode et activer les envois

Les deux interrupteurs sont indépendants et `false` par défaut :

- `RAIN_ALERTS_ENABLED=true` autorise l'évaluation ;
- `RAIN_ALERTS_SEND_ENABLED=false` conserve le shadow mode sans outbox ni FCM.

Le worker relit aussi `alertControl/runtime` dans Firestore à chaque passage.
Les champs booléens `engineEnabled` et `sendEnabled` peuvent donc arrêter le
moteur ou les envois sans build. Si le document n'existe pas, les valeurs de
l'environnement s'appliquent. Une coupure budgétaire met les deux champs à
`false` et reste bloquée au changement de mois jusqu'à réactivation manuelle.

Pendant 48 heures, conserver `sendEnabled=false`, inspecter les documents
`alertRunMetrics` et le dashboard, puis comparer `deliveriesProposed` avec
Graph/Radar. Le shadow mode met à jour l'état pluie : son activation ne produit
pas rétroactivement une notification pour un épisode déjà commencé.

## 5. Provisionner l'observabilité et le garde-budget

Après création du projet, lancer :

```sh
backend/deploy/alerts/provision-alert-observability.sh chetiwa

backend/deploy/alerts/provision-alert-budget-guard.sh \
  chetiwa europe-west1 IMAGE_BACKEND \
  chetiwa-alert-budget-guard@chetiwa.iam.gserviceaccount.com \
  chetiwa-alert-budget-invoker@chetiwa.iam.gserviceaccount.com \
  BILLING_ACCOUNT_ID \
  /chemin/absolu/chetiwa-alerts-staging.yaml
```

Le premier script crée six métriques de logs et le dashboard **Chetiwa —
Alertes pluie**. Le second déploie un endpoint Cloud Run privé, une souscription
Pub/Sub authentifiée et un budget mensuel de projet à 50 EUR avec seuils 50 %
(25 EUR) et 100 % (50 EUR). Les notifications Billing sont des estimations,
arrivent plusieurs fois par jour, au moins une fois et parfois dans le désordre ;
le store conserve le coût maximal de la période et ignore les périodes anciennes.

À 25 EUR, Cloud Billing avertit les destinataires IAM configurés et le contrôle
Firestore expose `softBudgetExceeded=true`. À 50 EUR, Chetiwa désactive son
moteur d'alertes ; il ne désactive jamais automatiquement la facturation du
projet entier. Ce seuil est un garde-fou applicatif, pas une limite bancaire
stricte : le reporting Billing peut être retardé et le coût réel peut dépasser
50 EUR avant réception du message. Aucun de ces scripts n'est exécuté
automatiquement par le dépôt.

Documentation officielle :

- <https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications>
- <https://cloud.google.com/run/docs/tutorials/pubsub>
- <https://cloud.google.com/sdk/gcloud/reference/billing/budgets/create>

Documentation officielle :

- <https://cloud.google.com/run/docs/execute/jobs-on-schedule>
- <https://firebase.google.com/docs/cloud-messaging/send/v1-api>
