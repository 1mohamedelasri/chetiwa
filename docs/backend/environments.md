# Environnements backend Chetiwa

Le backend suit l’ADR-0004 : un monolithe modulaire conteneurisé, exécutable en
local et destiné à trois projets strictement séparés.

| Environnement | État | Projet cloud | Données et fournisseurs |
|---|---|---|---|
| Local | Exécutable | Aucun | Fixtures, émulateurs et fournisseurs de développement |
| Staging | Profil prêt, projet à provisionner | Projet GCP dédié | Sandbox, clés staging et budgets très bas |
| Production | Profil prêt, projet à provisionner | Projet GCP dédié | Clés commerciales, consentement et quotas de production |

## Règles obligatoires

1. Aucun secret dans Git, l’image Docker ou l’application mobile.
2. `GOOGLE_CLOUD_PROJECT` est obligatoire hors local pour empêcher un déploiement
   accidentel dans le mauvais projet.
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
