# ADR-0008 — MVP local-first et activation des coûts par paliers

- Statut : Accepté
- Date : 2026-08-20
- Propriétaire : Produit/Operations Chetiwa
- Remplace pour le MVP les parties coûteuses des ADR 0002, 0004 et 0007 ; ces
  ADR restent applicables lorsque leurs gates sont franchis.

## Contexte

Chetiwa doit d'abord prouver que ses écrans météo sont utiles et que les
utilisateurs reviennent. Créer dès maintenant une base cloud, un moteur push,
un service d'analytics, un fond satellite et un contrat radar payant ferait
porter des coûts récurrents avant la moindre validation produit.

## Décision

Le MVP et la bêta fermée suivent un modèle **local-first, sans coût fixe
obligatoire** :

- pas de compte utilisateur, Firestore, Remote Config, service d'analytics ou
  moteur d'alertes serveur en prérequis ;
- pas de fond satellite, de publicités ni d'abonnements avant le gate de
  monétisation ;
- GPS demandé à l'action seulement ; recherche et lieux récents conservés sur
  l'appareil ;
- les préférences d'alertes déjà codées restent locales. Elles ne promettent pas
  une alerte fiable en arrière-plan tant que le moteur distant n'est pas activé ;
- le backend existant reste optionnel : il est exécuté localement pour les tests
  et n'est déployé sur Cloud Run, avec `min-instances=0`, que si le fournisseur
  de lancement impose un proxy afin de protéger une clé ou respecter sa licence ;
- toute donnée ou tuile externe ne peut servir à une distribution publique ou
  monétisée que si ses conditions écrites le permettent. Une offre gratuite ne
  doit jamais être supposée commerciale.

## Gates d'activation

| Brique | Ne pas activer avant | Condition d'activation |
| --- | --- | --- |
| Backend Cloud Run | Bêta locale/fermée | licence exige un proxy ou besoin de cache partagé ; budget mensuel fixé et alerte configurée |
| Firestore | Alertes multi-appareils ou droits Premium réels | besoin persistant démontré, schéma minimal, rétention et suppression définies |
| APNs/FCM + moteur d'alertes | Promesse « prévenir avant la pluie » en production | qualité mesurée en mode silencieux, coût par alerte connu, opt-in et désactivation testés |
| Radar commercial / nowcast | Distribution publique lorsque le contrat prototype ne suffit plus | droits commerciaux écrits, estimation tuiles/session, limite de frames et cache validés |
| Analytics / Crash cloud | Quand les journaux locaux ne suffisent plus à la bêta | inventaire des événements minimal et consentement conforme |
| Publicité et abonnement | Après validation de la rétention et de la valeur Premium | licences fournisseurs compatibles, coûts variables calculés et parcours store sandbox validé |
| Satellite | Jamais dans le MVP | revenu Premium couvre son coût avec marge de sécurité |

## Garde-fous

- Chaque service activé reçoit un plafond mensuel décidé par le propriétaire ;
  à 75 % le rollout est gelé, à 100 % la fonction coûteuse est coupée.
- Les coûts doivent être mesurés par session radar/alerte, pas seulement par
  installation.
- Le MVP ne doit pas présenter un contrôle non garanti comme une notification
  temps réel fiable.
- Une validation écrite des droits et une prévision de coût précèdent chaque
  activation de fournisseur.

## Conséquences

- Les endpoints devices/alertes et l'écran de préférences sont des fondations
  volontairement non déployées en production pour l'instant.
- Firebase n'est pas requis pour publier une bêta sans push distant, achats ou
  analytics cloud. Firebase Cloud Messaging peut être gratuit pour la livraison,
  mais le serveur, le stockage et les requêtes fournisseur nécessaires aux
  alertes ne le sont pas forcément.
- Le premier lancement public monétisé peut nécessiter un contrat de données :
  l'économie est donc validée avant, non après, cette signature.

## Références

- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Firebase Cloud Messaging](https://firebase.google.com/products/cloud-messaging)
- [Firestore pricing](https://firebase.google.com/docs/firestore/pricing)
