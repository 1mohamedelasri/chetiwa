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
   distincts. Firestore, Redis et Cloud CDN restent désactivés par défaut.
4. Cloud Run conserve `min-instances=0` et `max-instances=1` tant qu'aucun
   compteur partagé n'est configuré.
5. Les coordonnées précises ne sont pas journalisées.

## Provisionnement restant

La création effective d'un projet GCP, du compte de facturation, des budgets et
de Secret Manager nécessite l’accès propriétaire au compte Google Cloud. Une
base Firestore, Redis ou un CDN ne sont créés que si un gate de coût ultérieur
est franchi.
