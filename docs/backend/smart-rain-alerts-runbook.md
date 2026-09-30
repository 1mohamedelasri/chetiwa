# Smart Rain Alerts — activation APNs, Firestore, worker et budget

Le dépôt contient N0.1 à N0.8, mais il ne peut pas créer une clé privée Apple
ni choisir à la place du propriétaire l'emplacement irréversible de Firestore.
Ne jamais ajouter une clé `.p8`, un JSON de compte de service ou un token push
au dépôt.

## État opérationnel — 19 septembre 2026

Les deux schedulers du projet `chetiwa`, région `europe-west1`, sont
**`PAUSED`**, état confirmé par CLI après les vérifications :

| Scheduler | Job Cloud Run | Configuration vérifiée |
| --- | --- | --- |
| `chetiwa-rain-alerts-every-5m` | `chetiwa-rain-alerts` | `RAIN_ALERTS_ENABLED=false`, `RAIN_ALERTS_SEND_ENABLED=false` |
| `chetiwa-vigilance-alerts-every-5m` | `chetiwa-vigilance-alerts` | `VIGILANCE_ALERTS_ENABLED=false`, `VIGILANCE_ALERTS_SEND_ENABLED=false` |

Les 15 exécutions pluie inspectées déclaraient toutes `activeAlerts: 0` et
`pushSent: 0`. La pause évite les lancements inutiles toutes les cinq minutes.
La pause seule n'empêche pas une exécution manuelle. Les deux anciens jobs ont
donc aussi été mis à jour explicitement avec `ENABLED=false` et `SEND=false`,
puis ces quatre valeurs ont été vérifiées par CLI. Cela bloque leur évaluation
et leurs envois avec la configuration actuelle, y compris en lancement manuel.
Aucun job n'a été exécuté pour cette désactivation. **Ne pas réactiver ni
exécuter les anciennes images, même en shadow mode : elles pourraient encore
écrire un état privé sans respecter le protocole d'effacement.** Les données
existantes sont conservées ; créer une règle ne réactive aucun job.

Le scheduler vigilance conservait un état de programmation obsolète datant du
30 août. Une séquence pause/mise à jour/reprise a rétabli son déclenchement :
l'exécution automatique `chetiwa-vigilance-alerts-hnnt5` a été créée le
19 septembre à `11:00:00.991 UTC` et son journal à `11:00:55.662374 UTC`
indique `status: completed`, `mode: shadow`, `pushSent: 0`. Le scheduler a
ensuite été suspendu pour maîtriser les coûts. Cette preuve valide le
déclenchement automatique de l'image alors déployée ; elle ne valide ni les
nouvelles images décrites ci-dessous ni la réception FCM/APNs sur téléphone.

La seule politique TTL activée et vérifiée pendant cet audit est
**`alertRunMetrics.expiresAt: ACTIVE`**. Le code fixe son échéance à
`startedAt + 30 jours`. Ne pas lancer `provision-alert-store.sh` sur le projet
existant : ce script active huit politiques TTL et modifie aussi IAM et les
règles Firestore, au-delà du changement approuvé.

L'API Firebase Rules a aussi confirmé que la version Firestore publiée le
25 août 2026 refuse les lectures et écritures des clients avec
`allow read, write: if false`. Les accès backend restent régis par IAM.

Le budget Cloud Run affichait 5,03 EUR sur 10 EUR et une prévision de 9,01 EUR
pour septembre avant cette intervention. Ce sont les coûts suivis hors
économies, pas nécessairement le montant final à payer. Le plafond de dépenses
de 10 EUR reste configuré : contrairement à un budget d'alertes uniquement,
il peut suspendre Cloud Run à 100 %. Les dépenses déjà engagées peuvent encore
apparaître avec le délai de facturation.

Aucun service web Cloud Run n'était présent lors de la vérification. L'API
publique `https://chetiwa-api.ezplatforms.com/healthz` répondait HTTP 200 avec
`{"status":"ok"}` avant et après la suspension.

### Mise à jour des workers existants avant toute reprise

**Les deux images de workers doivent être reconstruites et remplacées avant
réactivation.** Les anciennes images ne respectent pas les nouvelles
protections contre les écritures après effacement d'un appareil. Le worker
pluie doit aussi contenir les écritures/suppressions conditionnelles des
calendriers de cellules, afin de préserver le réveil d'un nouvel abonné.
Déployer seulement l'API Hetzner ne met pas à jour ces exécutables Cloud Run.

Le téléversement de l'archive interne vers Cloud Build a été refusé par la
revue automatique d'approbation, car ce transfert dépasse l'inspection
autorisée. L'approbation du propriétaire est en attente ; **aucun transfert
de cette archive n'a été effectué**. La procédure ci-dessous reste à exécuter
après cette approbation et ne décrit pas un déploiement déjà réalisé.

1. Conserver les deux schedulers `PAUSED` et les quatre drapeaux
   `ENABLED`/`SEND` à `false`. Attendre la fin de toute ancienne exécution.
   Relever les digests et la configuration des jobs existants pour
   comparaison, sans publier les valeurs de secrets. Construire depuis le
   code corrigé et testé une image backend contenant les deux exécutables,
   la publier dans Artifact Registry et retenir son digest immuable.
2. Mettre à jour uniquement l'image et maintenir les deux drapeaux à `false`
   pour chaque job, jusqu'à vérification de la nouvelle image. Les
   commandes suivantes préservent les comptes de service, autorisations IAM,
   commandes d'exécution, références Secret Manager, autres variables et
   limites existantes. Remplacer le digest d'exemple avant exécution :

   ```sh
   CHETIWA_WORKER_IMAGE='europe-west1-docker.pkg.dev/chetiwa/chetiwa/chetiwa-backend@sha256:REMPLACER_PAR_LE_DIGEST_VALIDE'

   gcloud run jobs update chetiwa-rain-alerts \
     --project=chetiwa --region=europe-west1 \
     --image="$CHETIWA_WORKER_IMAGE" \
     --update-env-vars=RAIN_ALERTS_ENABLED=false,RAIN_ALERTS_SEND_ENABLED=false

   gcloud run jobs update chetiwa-vigilance-alerts \
     --project=chetiwa --region=europe-west1 \
     --image="$CHETIWA_WORKER_IMAGE" \
     --update-env-vars=VIGILANCE_ALERTS_ENABLED=false,VIGILANCE_ALERTS_SEND_ENABLED=false
   ```

   Comparer ensuite les configurations : seuls le digest et les drapeaux
   demandés doivent changer. Les commandes doivent toujours sélectionner
   `/app/chetiwa-alert-worker` et `/app/chetiwa-vigilance-worker`
   respectivement. Ne pas réexécuter les scripts de provisionnement pour
   cette mise à jour. [Référence `gcloud run jobs update`](https://docs.cloud.google.com/sdk/gcloud/reference/run/jobs/update).

   **Pour une mise à jour d'image uniquement, arrêter la procédure ici.**
   Relire chaque job et comparer son compte de service et sa commande à
   l'état précédent ; confirmer le nouveau digest, les quatre drapeaux à
   `false` et les deux schedulers toujours `PAUSED`. Ne pas ajouter
   `--execute-now`, lancer un job ni reprendre un scheduler dans cette étape.
   Les essais des étapes suivantes constituent une activation distincte,
   même sans envoi de notification, et nécessitent leur propre autorisation.
3. Vérifier le contrôle pluie `alertControl/runtime` dans Firestore **avant
   tout essai** : son champ `sendEnabled`, s'il existe, remplace le drapeau
   d'environnement. Il doit être `false`, ou absent avec l'environnement à
   `false`. Ne pas supprimer le document ni remettre à zéro ses compteurs ou
   sa coupure budgétaire. Confirmer les nouveaux digests et l'autorisation de
   ce test shadow, sans contourner un arrêt budgétaire. **Seulement alors**,
   activer explicitement l'évaluation des nouvelles images en conservant
   `SEND=false` et les schedulers en pause, puis les exécuter :

   ```sh
   gcloud run jobs update chetiwa-rain-alerts \
     --project=chetiwa --region=europe-west1 \
     --update-env-vars=RAIN_ALERTS_ENABLED=true,RAIN_ALERTS_SEND_ENABLED=false
   gcloud run jobs execute chetiwa-rain-alerts \
     --project=chetiwa --region=europe-west1 --wait

   gcloud run jobs update chetiwa-vigilance-alerts \
     --project=chetiwa --region=europe-west1 \
     --update-env-vars=VIGILANCE_ALERTS_ENABLED=true,VIGILANCE_ALERTS_SEND_ENABLED=false
   gcloud run jobs execute chetiwa-vigilance-alerts \
     --project=chetiwa --region=europe-west1 --wait
   ```

4. Pour chaque exécution, vérifier le digest utilisé, `status: completed`,
   `mode: shadow`, `pushSent: 0`, l'absence d'erreurs fournisseurs et les
   métriques attendues. Un résultat `disabled`, un passage sans règle active
   ou sans cellule due ne prouve pas l'évaluation réelle : compléter avec
   une règle de test consentie et contrôler les propositions, l'effacement
   de l'appareil et les calendriers. Mesurer aussi durée et coût Firestore.
5. Après réussite des tests manuels, valider une échéance automatique de
   chaque scheduler en shadow mode dans une fenêtre surveillée, puis les
   remettre en pause et confirmer `PAUSED`. Après la fenêtre de test, ou dès
   un échec, remettre également `ENABLED=false` et `SEND=false` sur les deux
   jobs avec les commandes suivantes. Conserver les identifiants
   d'exécution et journaux. La reprise durable et les envois réels exigent
   ensuite la validation du budget, du test FCM/APNs sur appareil, de
   l'opt-in et des heures silencieuses, ainsi qu'une décision explicite
   d'activation. Aucun simple `resume` de l'ancienne image n'est suffisant.

   ```sh
   gcloud run jobs update chetiwa-rain-alerts \
     --project=chetiwa --region=europe-west1 \
     --update-env-vars=RAIN_ALERTS_ENABLED=false,RAIN_ALERTS_SEND_ENABLED=false
   gcloud run jobs update chetiwa-vigilance-alerts \
     --project=chetiwa --region=europe-west1 \
     --update-env-vars=VIGILANCE_ALERTS_ENABLED=false,VIGILANCE_ALERTS_SEND_ENABLED=false
   ```

Vérification en lecture seule de la pause :

```sh
gcloud scheduler jobs describe chetiwa-rain-alerts-every-5m \
  --project=chetiwa --location=europe-west1 --format='value(state)'
gcloud scheduler jobs describe chetiwa-vigilance-alerts-every-5m \
  --project=chetiwa --location=europe-west1 --format='value(state)'
```

Références : [plafonds de dépenses Google Cloud](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps)
et [reprise d'un scheduler](https://docs.cloud.google.com/sdk/gcloud/reference/scheduler/jobs/resume).

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

Cette section décrit un **nouvel environnement**. Pour le projet `chetiwa`
existant, la base est déjà créée : ne pas répéter cette procédure. Seul le TTL
`alertRunMetrics.expiresAt` est actuellement activé et vérifié ; les sept
autres collections restent inchangées. Le script de provisionnement ne doit
pas élargir automatiquement cette rétention.

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

Le script vérifie que la base existe et active uniquement le TTL
`alertRunMetrics.expiresAt` (expiration écrite à 30 jours par le worker).
Il laisse inchangées les politiques des appareils, règles, états, livraisons
et calendriers. Il accorde l'accès Firestore/FCM au worker et déploie les règles
deny-all côté mobile. Il ne choisit et ne crée pas automatiquement la région.

Documentation officielle :

- <https://firebase.google.com/docs/firestore/quickstart>
- <https://firebase.google.com/docs/firestore/manage-databases>
- <https://cloud.google.com/firestore/docs/ttl>

## 3. Déployer le job N0.4–N0.6

Cette procédure concerne le provisionnement initial. Pour les deux jobs déjà
présents dans `chetiwa`, suivre la mise à jour ciblée de l'état opérationnel
ci-dessus ; ne pas recréer IAM, écraser l'environnement ni réactiver les
schedulers via les scripts de provisionnement.

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

Une fois explicitement réactivé, le Scheduler réveille le job toutes les cinq
minutes, mais le job ne contacte pas aveuglément le fournisseur pour chaque
cellule. Il lit le petit document Firestore `alertCellSchedules/{cellKey}` et
saute les cellules qui ne sont pas encore dues :

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
suivant. Les calendriers portent une échéance `expiresAt` à sept jours ; leur
suppression automatique nécessite la politique TTL `alertCellSchedules`, qui
n'a pas été activée pendant cet audit. Ils ne contiennent aucun token,
identifiant d'appareil ni coordonnée exacte d'utilisateur.

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

Cette estimation précède les protections de concurrence ajoutées le
19 septembre. Les écritures d'état et d'outbox ajoutent deux lectures et deux
écritures conditionnelles de contrôle ; remesurer les opérations et les coûts
en shadow mode avant d'utiliser ce tableau comme budget de lancement.

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
