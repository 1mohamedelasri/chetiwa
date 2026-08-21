# Chetiwa — Roadmap vers une application prête pour la production

> Objectif : publier une application météo fiable, conforme et économiquement
> contrôlable sur l’App Store et Google Play, puis l’exploiter sans que les coûts
> fournisseurs augmentent plus vite que les revenus.

Cette roadmap transforme la [spécification produit](Chetiwa%20%E2%80%94%20Product%2C%20UX%2C%20Flutter%20Architecture%20%26%20Monetization%20Specification%20v2.md)
en plan d’exécution. La [stratégie des fournisseurs](docs/data-provider-strategy.md)
reste la référence technique détaillée pour les données météo.

## Légende

- ✅ Socle déjà présent et à conserver.
- 🟡 Présent partiellement, à terminer ou durcir.
- ⬜ À réaliser.
- **Gate** : condition obligatoire avant de passer à la phase suivante.

## Périmètre actif à compter du 2026-08-20

Le travail actif porte sur la bêta locale-first : météo, Radar, recherche,
choix sur carte, GPS à la demande, cache, qualité et conformité minimale. Les
achats, la publicité, le satellite commercial et la synchronisation de compte
restent **hors périmètre de la bêta**. Après validation des revenus, la seule
intégration Firebase autorisée est **Firebase Analytics** (sans base de données,
Functions, Storage, Remote Config, Crashlytics ni push). Les publicités passent
directement par **AdMob / Google Mobile Ads**, qui ne requiert pas Firebase.

## Principes non négociables

1. Une ouverture doit donner rapidement une réponse météo compréhensible.
2. Graph, Radar et Prévisions utilisent toujours le même lieu, le même fuseau
   horaire et une chronologie cohérente.
3. Une donnée observée, une prévision et une probabilité ne sont jamais
   présentées comme si elles représentaient la même chose.
4. La publicité ne recouvre jamais la météo ni un contrôle interactif.
5. La localisation, les notifications, le tracking et la publicité personnalisée
   sont demandés uniquement au moment où l’utilisateur en comprend la valeur.
6. Aucune clé fournisseur secrète ne doit être embarquée dans l’application.
7. Une fonctionnalité payante ou coûteuse doit pouvoir être désactivée à distance.
8. Aucun lancement monétisé n’a lieu sans licence commerciale et attribution pour
   chaque fournisseur utilisé.
9. Aucune brique cloud ou fournisseur payant n'est un prérequis de la bêta : elle
   est activée uniquement après le gate défini dans
   [`ADR-0008`](docs/decisions/0008-lean-mvp-cost-gates.md).
10. Firebase Analytics est facultatif, gratuit et ne doit jamais entraîner
    l'activation implicite de produits Firebase facturables.

## Cible fournisseurs : mode MVP frugal

| Besoin | Développement actuel | Cible production | Règle de coût |
| --- | --- | --- | --- |
| Prévisions, Graph et Weather Brief | Open-Meteo | Fournisseur dont les droits correspondent au lancement choisi | Ne rien payer avant d'avoir validé le droit de bêta/public/monétisation et le coût maximal |
| Radar animé | RainViewer | Contrat écrit seulement si une distribution publique l'exige | Limiter frames, zoom et sessions ; ne pas supposer que le prototype est commercial |
| Fond de carte standard | CARTO/Esri | OpenFreeMap + MapLibre | Gratuit, attribution obligatoire, prévoir un repli car pas de SLA |
| Fond satellite | Esri | Hors MVP | Ne l’activer qu’avec quota, budget et revenu Premium établi |
| Recherche mondiale | Open-Meteo Geocoding | Proxy Chetiwa vers le fournisseur retenu | Cache, limitation et possibilité de remplacement |

La cible est une décision de lancement, pas un couplage du domaine. Tous les
fournisseurs restent derrière des repositories remplaçables. Le détail du mode
sans coût fixe est dans [`docs/business/lean-mvp-cost-plan.md`](docs/business/lean-mvp-cost-plan.md).

---

# Phase 0 — Gouvernance du produit et décisions

**Statut : terminée le 2026-08-20.** Les décisions sont enregistrées dans
[`docs/decisions`](docs/decisions/README.md) et restent révisables par un nouvel
ADR explicite.

## Livrables

- ✅ Spécification produit/UX/architecture v2.
- ✅ Stratégie initiale des fournisseurs de données.
- ✅ Registre des décisions (`docs/decisions/`) créé pour :
  - fournisseur météo ;
  - fournisseur radar ;
  - fond de carte ;
  - backend/hébergement ;
  - achats et gestion des droits Premium ;
  - publicité et CMP ;
  - analytics, crash reporting et notifications.
- ✅ Matrice Chetiwa Free / Chetiwa+ définie dans
  [`docs/product/free-premium-matrix.md`](docs/product/free-premium-matrix.md).
- ✅ Pays, langues et périmètre initial fixés dans
  [`docs/product/launch-scope.md`](docs/product/launch-scope.md).
- ✅ KPI et budgets maximums définis dans
  [`docs/business/kpi-budget-guardrails.md`](docs/business/kpi-budget-guardrails.md) : coût par utilisateur actif, coût radar,
  coût carte, revenu publicitaire et revenu Premium net.
- ✅ Registre fournisseur créé dans
  [`docs/compliance/provider-register.md`](docs/compliance/provider-register.md)
  avec licence, attribution, DPA, sous-traitants,
  politique de rétention, prix et date de dernière vérification.

## Gate 0

- ✅ Le MVP est figé et les fonctionnalités hors MVP sont identifiées.
- ✅ Chaque service externe possède un propriétaire, un budget et une solution de
  repli documentée.

---

# Phase 1 — Stabiliser le cœur météo existant

## État actuel

- ✅ Architecture Flutter par fonctionnalités, BLoC, repositories et injection.
- ✅ Weather Brief, Graph 2 h/24 h, Radar et Prévisions.
- ✅ Recherche mondiale, position courante, lieux récents et villes suggérées.
- ✅ Cache disque stale-while-revalidate pour prévisions et métadonnées radar.
- ✅ États fixtures et premiers tests unitaires/widgets.
- 🟡 Expérience Android/iOS réelle, précision et résilience à finaliser.

## Travaux

- ✅ Unifier toutes les horloges à partir d’un `WeatherClock` testable :
  - UTC pour stockage et échanges ;
  - fuseau du lieu pour affichage ;
  - gestion du changement d’heure et du passage à minuit.
- ✅ Garantir une seule source de vérité pour la pluie entre Weather Brief, Graph,
  Radar et Prévisions.
- ✅ Distinguer explicitement : observation radar passée, estimation actuelle,
  nowcast et prévision de modèle.
- ✅ Finaliser les états chargement, cache, hors-ligne, données périmées, couverture
  radar absente et fournisseur indisponible.
- ✅ Ajouter une bannière non bloquante « données mises à jour il y a… » lorsque le
  cache est ancien.
- ✅ Vérifier Graph/Radar pour pluie nulle, faible, modérée, forte et épisodes
  multiples avec les [scénarios météo de référence](docs/quality/weather-reference-scenarios.md).
  La neige/mixte reste explicitement hors validation tant que le flux de tuiles
  radar utilisé ne fournit pas un type d’hydrométéore distinct.
- ✅ Tester plusieurs villes et fuseaux dans le monde avec la
  [matrice mondiale des heures locales](docs/quality/world-time-zone-matrix.md),
  y compris changement de date, décalage de 45 minutes et heure d’été dans les
  deux hémisphères.
- ✅ Vérifier le comportement réseau lent, coupé, intermittent et reprise après
  mise en arrière-plan. Le protocole et les preuves sont consignés dans la
  [matrice de préparation](docs/quality/app-readiness-matrix.md).
- ✅ Finaliser thème clair/sombre, orientation, tailles d’écran et text scaling.
  Les profils automatisés couvrent petit téléphone à 200 %, téléphone standard,
  paysage compact et tablette.
- ✅ Auditer toutes les chaînes et terminer l’internationalisation FR/EN, y
  compris les textes dessinés dans les Graph/Radar et les erreurs de localisation.

## Gate 1

- ✅ `flutter analyze` et tous les tests passent.
- ✅ Aucun écran météo principal ne devient vide après une première synchronisation.
- ✅ Graph, Radar et Prévisions affichent le même lieu et des heures cohérentes.
- ✅ Les cinq scénarios météo de référence sont validés visuellement sur iOS
  Simulator et Android Emulator, sur Graph, Radar et Prévisions. Les 30
  captures reproductibles sont archivées dans
  [`docs/quality/screenshots`](docs/quality/screenshots), sans remplacer le
  smoke test final sur appareils physiques avant publication.

---

# Phase 2 — Backend Chetiwa optionnel et maîtrise des fournisseurs

Le backend modulaire existe déjà mais n'est déployé que si un fournisseur de
production impose un proxy ou un cache partagé. Il ne faut pas provisionner une
base cloud, un moteur push ou Remote Config pour la bêta frugale.

## API et infrastructure

- 🟡 Créer les environnements local, staging et production :
  - ✅ socle API conteneurisé, profil local exécutable et profils de
    configuration staging/production sans secrets ;
  - ⬜ **Après Gate coût** : provisionner seulement Cloud Run staging/production,
    budget et compte de service ; garder `min-instances=0` et `max-instances=1`.
    Firestore et Secret Manager ne sont ajoutés que lorsqu'ils deviennent requis.
- 🟡 Implémenter une API versionnée :
  - ✅ `GET /v1/forecast` ;
  - ✅ `GET /v1/locations/search` ;
  - ✅ `GET /v1/locations/reverse` ;
  - ✅ `GET /v1/radar/frames` ;
  - 🟡 `POST /v1/devices` et suppression du device : fondation terminée ;
    volontairement non déployée tant que les alertes distantes ne franchissent pas
    leur Gate ;
  - 🟡 CRUD des règles d’alerte : fondation typée terminée ; persistance cloud et
    moteur restent reportés après validation de l'utilité des alertes ;
  - ⬜ validation/synchronisation des droits Premium.
- ⬜ Stocker les secrets dans le gestionnaire de secrets de l’hébergeur.
- 🟡 Ajouter cache serveur, ETag, compression et stale-if-error :
  - ✅ cache mémoire LRU borné, `ETag`/`304`, gzip et repli stale-if-error ;
  - ⬜ cache distribué et métriques avant production.
- 🟡 Ajouter rate limiting par appareil/IP, protection anti-abus et quotas :
  - ✅ limite locale par instance et par identifiant d'installation, avec repli
    IP, réponse `429` et `Retry-After` ;
  - ⬜ limite distribuée, attestation d'application, quotas par environnement et
    kill switch pilotable.
- 🟡 Ne jamais journaliser des coordonnées précises inutilement : les quatre
  routes publiques actuelles n'en journalisent aucune et leurs clés de cache
  arrondissent les coordonnées à trois décimales ; appliquer la même règle aux
  futures routes devices/alertes et aux métriques.
- ⬜ **Après activation d'une base** : migrations, sauvegardes et restauration.
- ⬜ **Après Gate cloud** : feature flags distants ; avant cela, conserver des
  limites locales et variables de déploiement documentées.

## Migration fournisseurs

- ✅ Basculer les prévisions mobiles vers le proxy Chetiwa avec contrats
  normalisés, identifiant privé d'installation, `ETag` et cache disque SWR.
- ✅ Basculer la recherche mondiale et le reverse geocoding vers le proxy
  Chetiwa ; une position GPS brute reste utilisable si le libellé est indisponible.
- 🟡 Basculer Radar vers le proxy Chetiwa : métadonnées et chronologie passent
  par l'API ; les tuiles restent chargées depuis l'URL licenciée fournie par le
  backend jusqu'à la décision proxy/CDN de production.
- ✅ Interdire le fallback fournisseur direct en build production et imposer
  une URL backend HTTPS ; le fallback reste opt-in en développement seulement.
- ✅ Valider le parcours proxy sans fallback sur Android Emulator et iOS
  Simulator pour Graph, Radar et Prévisions, puis compiler Android release et
  iOS avec le profil production HTTPS. Protocole :
  [`docs/backend/mobile-proxy-integration.md`](docs/backend/mobile-proxy-integration.md).
- ⬜ Vérifier les droits exacts du fournisseur choisi avant chaque bêta publique,
  publicité ou abonnement ; ne souscrire que si le gate est franchi.
- ⬜ Remplacer RainViewer ou signer un contrat seulement si les droits de la
  distribution publique l'imposent.
- ⬜ Remplacer le fond principal par OpenFreeMap/MapLibre avec attribution.
- ⬜ Garder Esri satellite désactivé par défaut et réservé à Chetiwa+.
- ⬜ Implémenter les limites de zoom, nombre de frames, préchargement et cache afin
  de maîtriser le nombre de tuiles.
- ✅ Écran « Sources et licences » accessible depuis Settings, avec attributions
  et liens vers les conditions des sources actuellement visibles.

## Observabilité et coûts

- ⬜ Monitoring des latences, taux d’erreur, fraîcheur des données et cache hit rate.
- ⬜ Alertes à 50 %, 75 % et 90 % de chaque quota fournisseur.
- ⬜ Tableau de bord coût par jour, utilisateur actif, session Radar et abonné.
- ⬜ Budget mensuel et kill switch automatique avant dépassement critique.
- ⬜ Runbook de panne et bascule vers cache/fixture de continuité.

## Gate 2

- Aucune clé payante n’est extractible de l’APK ou de l’IPA.
- Le backend supporte une panne fournisseur sans rendre l’application inutilisable.
- Les budgets et alertes de consommation sont testés en staging.
- Les licences et attributions sont approuvées pour l’usage commercial prévu.

---

# Phase 3 — Localisation et choix direct sur la carte

## Recherche et sélection

- ✅ Recherche par ville/code postal, position actuelle et lieux récents.
- ✅ Créer un écran plein écran « Choisir sur la carte ».
- ✅ Afficher un repère fixe au centre ; la carte se déplace sous le repère.
- ✅ Pendant le déplacement, afficher un libellé temporaire sans lancer des appels
  réseau à chaque pixel.
- 🟡 Au relâchement, effectuer un reverse geocoding avec debounce : le proxy
  Chetiwa résout ville/région quand il est actif ; sans proxy, l'application
  confirme le point et ses coordonnées sans ajouter de fournisseur.
- ✅ Boutons : « Ma position », « Rechercher », « Confirmer ce lieu » et annuler.
- ✅ Afficher ville, région, pays et coordonnées si aucune adresse n’est trouvée.
- 🟡 Associer correctement fuseau horaire, locale et unité au lieu choisi : le
  fuseau vient déjà du fournisseur, la langue est persistée et le choix
  Celsius/Fahrenheit est désormais persistant et appliqué aux résumés, cartes
  horaires et quotidiennes.
- ✅ Mettre à jour Graph, Radar, Prévisions et alertes avec un objet `Location`
  unique et immuable : le lieu actif est partagé en mémoire et le lieu principal
  persiste localement ; les alertes locales affichent ce même lieu.

## GPS et permissions

- ✅ Demander uniquement la localisation « pendant l’utilisation » après action.
- ✅ Gérer : refus temporaire, refus permanent, service GPS coupé, timeout,
  précision faible et dernière position connue. Une position réduite ou la
  dernière position connue est explicitement signalée à l'utilisateur.
- ✅ Proposer l’ouverture des réglages système lorsque nécessaire.
- ✅ Ne pas demander la localisation en arrière-plan pour le MVP.
- ✅ Permettre de supprimer les lieux récents et désactiver la position courante :
  les récents se suppriment par glissement ; la position GPS est ponctuelle,
  n'est ni enregistrée ni suivie en arrière-plan.
- ✅ Tests widget automatisés des cas permission bloquée, GPS désactivé,
  localisation approximative et dernière position connue, y compris l’action de
  récupération adaptée.

## Lieux enregistrés

- ✅ Free : un lieu principal, enregistré uniquement sur l'appareil et
  remplaçable lors d'une nouvelle sélection.
- ⬜ Chetiwa+ : plusieurs lieux nommés (Maison, Travail, etc.).
- ⬜ Réordonner, renommer, supprimer et choisir le lieu par défaut.
- ⬜ Configurer les alertes séparément pour chaque lieu.

## Gate 3

- L’utilisateur peut obtenir une météo sans donner sa localisation.
- Recherche, GPS et choix sur carte produisent exactement le même modèle de lieu.
- Les parcours refus de permission et GPS désactivé sont testés sur iOS/Android.

**Prochaine vérification manuelle (sans coût) :** exécuter cette matrice sur un
iPhone et un Android physiques avant la bêta : permission refusée puis accordée,
GPS désactivé, localisation approximative, timeout, dernière position connue,
et sélection d'un lieu sans accorder l'accès GPS.

---

# Phase 4 — Smart Rain Alerts et notifications (après validation produit)

## Expérience utilisateur

- ✅ Afficher un écran explicatif avant le popup système.
- ✅ Demander l’autorisation uniquement quand l’utilisateur active une alerte.
- 🟡 Proposer : délai avant pluie, intensité minimale, lieux, heures silencieuses et
  activation/désactivation globale : délai, seuil, quiet hours et interrupteur
  global sont terminés localement ; sélection multi-lieux et persistance serveur
  restent à relier.
- ⬜ Permettre d’ouvrir directement le bon lieu et la bonne timeline depuis la
  notification.
- 🟡 Afficher l’état exact : autorisée ou bloquée par le système est affiché ;
  refus explicite et token invalide attendent APNs/FCM et le backend persistant.
- ✅ Préparer le client Flutter typé pour enregistrer/supprimer un device et
  créer, lire, modifier ou supprimer ses règles via l’API Chetiwa.

## Décision MVP

- ✅ L'écran et les préférences locales sont prêts ; aucune alerte « temps réel »
  fiable n'est promise ni activée en arrière-plan dans la bêta frugale.
- ⬜ Débloquer cette phase seulement après quatre semaines de bêta, une mesure de
  précision en mode silencieux et un plafond de coût par alerte validé.

## Infrastructure push — reportée derrière Gate

- ⬜ Configurer APNs, Firebase Cloud Messaging et environnements staging/prod.
- 🟡 Enregistrer et renouveler les tokens sans les associer à plus de données que
  nécessaire : contrat sécurisé et stockage local/test terminés ; APNs/FCM et
  Firestore restent à brancher.
- 🟡 Supprimer le token à la désactivation ou à la demande de suppression :
  suppression API en cascade terminée ; persistance cloud à valider.
- ⬜ Construire le moteur d’alertes serveur à partir du nowcast.
- ⬜ Dédupliquer les alertes d’un même épisode de pluie.
- ⬜ Ajouter cooldown, anti-spam, quiet hours et limites par appareil/lieu.
- ⬜ Recalculer lorsque la prévision change significativement.
- ⬜ Ne jamais dépendre d’un processus Flutter en arrière-plan pour garantir une
  alerte.
- ⬜ Instrumenter envoi, livraison lorsque disponible, ouverture et désactivation.

## Qualité des alertes

- ⬜ Constituer un jeu de cas réels et mesurer faux positifs, faux négatifs et écart
  entre heure annoncée et pluie observée.
- ⬜ Lancer d’abord en mode interne silencieux pour comparer sans notifier.
- ⬜ Déployer par pays/zone de couverture radar avec feature flag.
- ⬜ Afficher une formulation prudente lorsque la confiance est faible.

## Gate 4

- Aucune notification en double pendant les scénarios de charge et de retry.
- Désactiver les alertes empêche tout nouvel envoi.
- La suppression d’un appareil supprime token et règles associées.
- Les seuils de qualité météo définis en Phase 0 sont atteints.

---

# Phase 5 — Monétisation contrôlée (une seule voie au départ)

## Offre et paywall

- ⬜ Après validation de la rétention, choisir une seule première voie : Premium
  **ou** publicité. Ne pas intégrer les deux SDK avant d'avoir la réponse.
- ⬜ Finaliser Free/Chetiwa+ et les prix à tester si Premium est retenu.
- ⬜ Chetiwa Free reste utile : Brief, Graph, Radar essentiel et un lieu.
- ⬜ Chetiwa+ : pas de pub, Smart Alerts, multi-lieux, satellite et Radar étendu.
- ⬜ Ne pas afficher le paywall au premier lancement.
- ⬜ Présenter le Premium au moment d’une intention claire, par exemple « Me
  prévenir avant cette pluie ».
- ⬜ Afficher prix local, période, renouvellement, essai éventuel et conditions.
- ⬜ Implémenter restaurer les achats et gérer pending, grace period, remboursement,
  révocation, expiration et changement d’appareil.

## Achats

- ⬜ Conserver `SubscriptionRepository` indépendant de StoreKit/Google Billing.
- ⬜ Choisir et documenter : service géré d’entitlements ou validation serveur
  directe des reçus Apple/Google.
- ⬜ Créer les produits dans App Store Connect et Play Console.
- ⬜ Vérifier les droits côté serveur ; l’UI locale seule ne fait jamais foi.
- ⬜ Recevoir les notifications serveur Apple/Google pour renouvellements,
  remboursements et révocations.
- ⬜ Tester tous les scénarios avec comptes sandbox.

## Publicité

- 🟡 Frontières `AdsRepository` et `ConsentRepository` créées en mode désactivé :
  aucune dépendance publicitaire, requête ni collecte n'est embarquée. Intégrer
  le SDK publicitaire seulement si la voie publicité est retenue après la bêta.
- ⬜ Utiliser `google_mobile_ads` et un compte AdMob : **Firebase n'est pas
  requis** pour afficher, mesurer ou rémunérer les publicités.
- ⬜ Intégrer une CMP/UMP derrière `ConsentRepository`.
- ⬜ N’initialiser les publicités qu’après consentement lorsque requis.
- ⬜ Utiliser uniquement le slot réservé entre contenu et navigation.
- ⬜ Aucun interstitiel au lancement, aucun rafraîchissement pendant un scrub.
- ⬜ Supprimer totalement le slot pour Chetiwa+.
- ⬜ Ajouter option de modifier/retirer le consentement dans Settings.

## Mesure produit — Firebase Analytics uniquement (facultatif)

- ⬜ Après la bêta, intégrer uniquement Firebase Analytics pour comprendre les
  usages essentiels et, si AdMob est actif, rapprocher revenus publicitaires et
  parcours produit.
- ⬜ Limiter les événements aux décisions produit utiles : ouverture, changement
  d’onglet, recherche de lieu, activation d’alerte, affichage de publicité et
  achat/restauration. Ne pas envoyer d’adresse, de coordonnées précises ni de
  texte saisi par l’utilisateur.
- ⬜ Demander/recueillir le consentement requis et documenter Firebase Analytics
  dans la politique de confidentialité et les déclarations App Store/Play.
- ⬜ Rester sur les produits Analytics gratuits : ne pas activer Firestore, Realtime
  Database, Cloud Functions, Cloud Storage, FCM, Remote Config, Crashlytics ou
  tout produit Google Cloud sans nouvelle décision, budget et plafond de coût.

## Protection économique

- ⬜ Mesurer revenu et coût par utilisateur Free/Premium.
- ⬜ Si Firebase Analytics est activé, lier AdMob à Firebase uniquement pour lire
  les métriques agrégées ; cette liaison reste facultative et ne change pas
  l'intégration publicitaire dans l'application.
- ⬜ Fixer un plafond de frames Radar et requêtes par session Free.
- ⬜ Rendre le satellite disponible uniquement lorsque les revenus couvrent son
  coût avec marge de sécurité.
- ⬜ Ne pas activer la voie retenue tant que les licences de données et les coûts
  maximums sont compatibles avec la distribution envisagée.

## Gate 5

- Achats, restauration, expiration et remboursement fonctionnent sur les deux
  stores en sandbox.
- Un utilisateur Premium ne reçoit ni publicité ni tracking publicitaire.
- Les coûts estimés restent sous les plafonds pour trois scénarios de croissance.

---

# Phase 6 — Confidentialité, légal et sécurité

## Confidentialité et conformité

- 🟡 Rédiger et publier Politique de confidentialité et Conditions d’utilisation :
  brouillons bêta et écrans in-app terminés ; URL publique, identité légale et
  revue compétente restent obligatoires avant distribution externe.
- ⬜ Expliquer clairement l’usage de : localisation, notifications, identifiants
  publicitaires, analytics, crash logs, achats et lieux enregistrés.
- ⬜ Tenir un inventaire des données : finalité, base légale, durée, stockage,
  destinataires et pays de traitement.
- ⬜ Signer/archiver les DPA nécessaires avec les sous-traitants.
- ⬜ Définir des durées de rétention courtes et une purge automatique.
- 🟡 Le MVP sans compte propose maintenant l'effacement des lieux, caches et
  préférences locales, alertes et identifiant d'installation depuis Réglages.
  Export/suppression côté serveur seront requis uniquement si un compte ou
  stockage cloud est ajouté.
- ⬜ Fournir une adresse de contact confidentialité/support (à choisir par le
  propriétaire avant publication).
- ⬜ Remplir Apple Privacy Nutrition Labels et Google Play Data Safety à partir du
  comportement réel de l’application.
- ⬜ Vérifier RGPD/ePrivacy, consentement publicitaire, ATT iOS si tracking et règles
  applicables aux pays de lancement avec un conseil juridique compétent.
- ⬜ Choisir explicitement l’audience d’âge ; ne pas déclarer une application enfant
  sans implémenter les obligations correspondantes.

## Sécurité

- 🟡 Modèle de menace MVP local-first documenté dans
  [`docs/security/threat-model-mvp.md`](docs/security/threat-model-mvp.md) ; à
  réviser obligatoirement avant ajout de compte, achat, publicité, push ou cloud.
- ⬜ TLS partout, secrets hors mobile, rotation des clés et séparation staging/prod.
- ⬜ Restreindre les tokens fournisseurs par service/origine lorsque possible.
- ⬜ Valider toutes les entrées API et limiter tailles, fréquences et coordonnées.
- ⬜ Chiffrer les données sensibles au repos et réduire la précision stockée.
- 🟡 Analyse statique dans CI et mises à jour hebdomadaires via Dependabot ; un
  scan des dépendances et une procédure de correction restent à formaliser avant
  release candidate.
- ⬜ Préparer réponse aux incidents, révocation de clés et notification de violation.
- ⬜ Effectuer une revue sécurité avant release candidate.

## Gate 6

- Les déclarations stores correspondent exactement aux SDK et données réels.
- Un parcours utilisateur permet de modifier les consentements et supprimer les
  données concernées.
- Aucun secret ou identifiant de test n’est présent dans les builds de production.

---

# Phase 7 — Qualité industrielle et CI/CD

## Tests automatisés

- ✅ Premiers tests providers, cache, horloge, localisation et navigation.
- ⬜ Atteindre une couverture utile des règles domaine et BLoCs critiques.
- ✅ Tests contractuels et fixtures enregistrées pour Open-Meteo, RainViewer et
  le contrat normalisé du backend Chetiwa.
- 🟡 Goldens de référence : Graph en thème sombre et clair avec nom de lieu long,
  Radar sans tuiles distantes, Prévisions et indisponibilité de données. Restent
  les états carte distante, tous les formats écran et la revue humaine des images.
- 🟡 Tests d’intégration : les parcours critiques sélection de ville ou sur carte
  → Graph → Radar → Prévisions sont automatisés avec fixtures et validés sur
  Android Emulator et iOS Simulator. Restent à couvrir onboarding, alertes,
  achat, restauration et consentement lorsque ces dernières fonctions franchiront
  leur gate produit.
- ✅ Tests backend : device privé, validation, rate limits, cache/ETag,
  stale-if-error et CRUD d'alertes local de développement. L'authentification
  distribuée et les alertes distantes restent hors MVP.
- ⬜ Tests end-to-end sur au moins deux appareils iOS et deux Android représentatifs.

## Performance et robustesse

- ⬜ Mesurer cold start, temps jusqu’au premier Brief, FPS carte/graph et mémoire.
- ⬜ Profiler consommation batterie, données mobiles et stockage cache.
- ✅ Cache local borné : les caches Forecast et Radar conservent au plus huit
  lieux récemment utilisés chacun et évacuent le moins récent.
- 🟡 Zones tactiles principales couvertes par les composants Material ; les
  animations non essentielles respectent désormais « Réduire les animations ».
  Une vérification tactile simple sur appareils physiques reste à réaliser.
- ⬜ Tester réseau 3G, mode économie d’énergie et appareils bas de gamme.

## CI/CD

- 🟡 Pipeline GitHub Actions ajouté : format, analyse et tests Flutter/Dart, tests
  contractuels du backend et build Android debug sur chaque push/PR, avec APK de
  revue conservé 7 jours. Le build iOS signé reste à brancher après création du
  compte Apple et des certificats.
- ⬜ Signature et secrets uniquement dans le système CI sécurisé.
- ⬜ Génération reproductible des builds, numéros de version et changelog.
- ⬜ Distribution automatique vers TestFlight et Play Internal Testing.
- ⬜ Crash reporting et symboles/dSYM/proguard mappings correctement envoyés.

## Gate 7

- Zéro erreur bloquante connue, aucun crash reproductible critique.
- Objectifs de performance et robustesse atteints.
- Un release candidate peut être reconstruit et distribué depuis CI uniquement.

---

# Phase 8 — Préparation App Store et Google Play

## Identité et contenu

- ⬜ Valider nom, marque, bundle ID/application ID et domaines.
- ⬜ Finaliser icône, splash, captures, vidéo éventuelle et textes localisés.
- ⬜ Créer URL support, confidentialité, conditions et page marketing.
- ⬜ Préparer FAQ : précision météo, radar, alertes, achats et suppression.

## Configuration stores

- ⬜ Comptes développeur, contrats, fiscalité et coordonnées bancaires.
- ⬜ Certificats iOS, profils, clés APNs et signature Android protégés.
- ⬜ App Privacy, Data Safety, content rating et déclarations publicitaires.
- ⬜ Export compliance/chiffrement et permissions justifiées.
- ⬜ Métadonnées et captures de chaque abonnement/in-app purchase.
- ⬜ Comptes de review ou parcours sans compte, instructions Radar/Alerts/Premium.
- ⬜ Vérifier suppression de compte dans l’app si un compte est ajouté plus tard.

## Gate 8

- TestFlight et Play Closed Testing installables depuis une installation propre.
- Liens légaux publics et formulaires stores finalisés.
- Les reviewers peuvent tester les achats, restaurer et comprendre les permissions.

---

# Phase 9 — Bêta, validation météo et lancement

## Bêta

- ⬜ Alpha équipe sur plusieurs villes et événements de pluie réels.
- ⬜ Bêta fermée avec utilisateurs externes et canal de feedback dans l’app.
- ⬜ Comparer régulièrement Chetiwa à observations locales et sources de référence,
  sans chercher à reproduire exactement la palette d’une autre application.
- ⬜ Mesurer activation, D1/D7, ouverture Graph/Radar, qualité perçue et coûts.
- ⬜ Corriger les cinq principaux motifs d’abandon/crash avant lancement.
- ⬜ Tester le moteur d’alertes en mode silencieux puis sur petit groupe.

## Lancement progressif

- ⬜ Publier d’abord sur un nombre limité de pays.
- ⬜ Déploiement progressif avec arrêt automatique si crashs, erreurs ou coûts
  dépassent les seuils.
- ⬜ Support et runbook disponibles le jour du lancement.
- ⬜ Ne lancer les publicités qu’après validation du consentement en production.
- ⬜ Ne lancer Chetiwa+ qu’après validation des achats et entitlements en production.

## Gate 9 — Definition of Done v1

- L’utilisateur obtient une réponse météo utile avec recherche, GPS ou choix carte.
- Graph, Radar, Prévisions et notifications restent cohérents.
- Le hors-ligne et une panne fournisseur ont un comportement compréhensible.
- Les permissions sont contextuelles et révocables.
- Les achats/restaurations fonctionnent et Premium ne contient aucune publicité.
- Licences, attributions, confidentialité et déclarations stores sont à jour.
- Les coûts sont monitorés, plafonnés et associés à des métriques de revenu.
- Les équipes peuvent diagnostiquer, désactiver et restaurer chaque service critique.

---

# Phase 10 — Exploitation après lancement

- ⬜ Revue quotidienne crashs, erreurs fournisseurs, alertes push et dépenses la
  première semaine ; hebdomadaire ensuite.
- ⬜ Suivre installations, activation, D1/D7/D30, Weekly Weather Decisions,
  conversion Premium, churn et revenu par utilisateur.
- ⬜ Suivre la qualité météo par région et désactiver les zones insuffisantes.
- ⬜ Répondre aux avis stores et tickets support avec SLA interne.
- ⬜ Mettre à jour mensuellement dépendances et trimestriellement licences/DPA.
- ⬜ Tester sauvegarde/restauration et procédure incident régulièrement.
- ⬜ Ajuster prix et limites uniquement à partir des coûts et cohortes réelles.
- ⬜ Ajouter ensuite widgets, synchronisation de compte et nouvelles couches météo
  seulement si le cœur v1 est stable et rentable.

## Ordre d’exécution immédiat

1. Implémenter « Choisir sur la carte », terminer les permissions GPS et les
   tests sur appareils physiques — sans nouveau fournisseur payant.
2. Réaliser une bêta fermée locale-first, sans publicité, achat, satellite ni
   alerte distante, puis mesurer quatre semaines de rétention, fiabilité et
   trafic radar.
3. Vérifier les droits et chiffrer le coût réel du **seul** fournisseur nécessaire
   au prochain niveau de distribution ; activer un proxy Cloud Run seulement si
   cette licence l'impose.
4. Décider une seule voie de revenus, la valider en sandbox, puis activer les
   alertes serveur uniquement si son coût et sa précision sont justifiés.
5. Terminer confidentialité, sécurité, CI/CD et dossiers stores selon les SDK
   réellement activés.
6. Lancer progressivement avec plafonds et kill switches, puis ajouter les
   options coûteuses seulement si le revenu et l'usage les financent.

La priorité reste toujours la même : une météo cohérente et utile avant la
monétisation, puis une monétisation dont le revenu couvre les coûts variables.
