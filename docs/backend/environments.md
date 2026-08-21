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
3. Staging et production utilisent des comptes de service, bases Firestore,
   budgets et clés distincts.
4. Cloud Run conserve `min-instances=0` et une limite initiale de trois instances.
5. Les coordonnées précises ne sont pas journalisées.

## Provisionnement restant

La création effective des deux projets GCP, du compte de facturation, des
budgets, de Secret Manager et de Firestore nécessite l’accès propriétaire au
compte Google Cloud. Elle doit être réalisée avant de considérer le premier item
de Phase 2 comme complètement terminé.
