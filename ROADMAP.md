Verdict
GO technique pour une bêta contrôlée après déploiement des profils versionnés. Les P0 applicatifs Graph/Radar sont corrigés et testés sur Android et iPhone. Un lancement public avec SLA reste NO-GO tant que le tunnel Cloudflare, le cache LibreWXR réellement déployé et les métriques de latence froide ne sont pas stabilisés.
Le 23 août 2026, l’URL publique LibreWXR a renvoyé cinq `502` consécutifs alors que les fonds Esri répondaient en 70–120 ms, puis elle est revenue en `200`. Cette intermittence confirme le besoin du watchdog. Après récupération, Paris chaud répondait en 37–44 ms (`CF-Cache-Status: HIT`) ; une première tuile Sierra Leone froide a demandé 5,53 s (`MISS`), puis 40 ms (`HIT`).
Le 24 août, cinq sondes métadonnées sur cinq répondaient en 61–144 ms, mais `/health` montrait toujours un seul worker, 64 Mo de cache, seulement 19 minutes d’uptime, 0 % de hit interne sur l’instance redémarrée et 6,23 s de latence moyenne par tuile. Le client est prêt ; l’exploitation ne l’est pas encore pour un SLA public.

## Roadmap production — Smart Rain Alerts sans compte

**Objectif :** prévenir avant la pluie sur Android et iPhone, même lorsque
l’application est fermée, sans compte Chetiwa. Budget cible à 50 000 appareils :
**25 €/mois**, arrêt automatique du moteur à **50 €/mois**. FCM/APNs reste à
0 € par message ; les dépenses concernent uniquement calcul, stockage et données.

### P0 — obligatoire avant la production

| Ordre | Livrable minimal | Critère de fin |
| --- | --- | --- |
| **N0.1 — implémenté dans le code** | `firebase_messaging`, auto-init après opt-in seulement, renouvellement/suppression du token, présentation au premier plan, handler arrière-plan, canal Android, capability/entitlements APNs et permission iOS. | Builds Android/iOS réussis. Reste à téléverser la clé APNs dans Firebase et recevoir un vrai push en premier plan, arrière-plan et après fermeture normale sur les deux appareils. |
| **N0.2 — implémenté** | Identifiant aléatoire par installation déjà partagé avec l’API ; envoi de `platform`, token, langue, fuseau du téléphone et version de l’app ; aucun compte/e-mail/identifiant publicitaire. Désactivation et suppression locale révoquent token et règles, avec retry persistant. | Tests d’enregistrement anonyme, fallback sans autorisation et suppression réussis ; token/hash absents des réponses. Validation réinstallation physique encore à effectuer. |
| **N0.3 — implémenté dans le code** | Adaptateur Firestore par hash d’installation, sous-collection d’alertes, suppression atomique, TTL 180 jours, ADC Cloud Run, règles sans accès mobile et script IAM/TTL. Redis reste exclu. | Persistance après recréation du store, isolation et cascade testées. Reste à créer la base staging/production et exécuter `backend/deploy/firestore/provision-alert-store.sh`. |
| **N0.4 — implémenté dans le code** | Binaire Cloud Run Job et Scheduler 5 minutes ; cellules stables de `0,05°`, concurrence bornée, une requête LibreWXR par cellule avec repli Open-Meteo ; lease Firestore de 10 minutes contre les exécutions concurrentes/at-least-once. | Mutualisation et second passage idempotent testés. Reste à déployer le job staging avec `RAIN_ALERTS_ENABLED=true` et mesurer sa p95 avec le nombre réel de cellules. |
| **N0.5 — implémenté** | Passage `sec → pluie prévue`, seuil/délai choisis, identifiant déterministe appareil+règle+épisode, cooldown 120 minutes, réalerte uniquement lors du passage à forte, quiet hours dans le fuseau du téléphone et plafond 6/jour local. | Même épisode sans doublon et quiet hours testés. Reste le mode silencieux 48 h pour mesurer faux positifs et retard sur données réelles. |
| **N0.6 — implémenté dans le code** | Outbox Firestore dédupliquée ; FCM HTTP v1 par ADC ; TTL/collapse 30 minutes ; retry exponentiel `429/5xx` ; token `UNREGISTERED` désactivé ; payload sans secret avec lieu, intensité, heure locale et `eventId`. Un toucher ouvre Radar au lieu du push, y compris après cold start. | Payload, retry, nettoyage du token et navigation mobile testés. Reste à activer FCM/APNs et valider un vrai push Android/iPhone en premier plan, arrière-plan et app fermée. |
| **N0.7 — implémenté** | Tant que l’enregistrement distant n’a jamais réussi, conserver l’alerte locale. Après le premier succès, une panne temporaire conserve la propriété distante et annule le local ; retour local uniquement après désactivation distante explicite. | Scénarios avant/après inscription testés : panne initiale avec fallback local, panne de refresh sans doublon, désactivation persistante. |
| **N0.8 — implémenté dans le code** | Shadow mode sans FCM, contrôle distant Firestore `engineEnabled/sendEnabled`, métriques agrégées avec TTL 30 jours et logs sans token/coordonnées ; dashboard Cloud Monitoring ; budget projet à 25 €/50 € via Cloud Billing Pub/Sub, endpoint privé et coupure persistante du moteur à 50 €. | Tests shadow, parsing du schéma Billing, messages dupliqués/hors ordre et hard cutoff réussis. Reste à exécuter les scripts cloud, vérifier l’e-mail à 25 €, le dashboard et une coupure staging à 50 € simulée. |

### Validation et lancement rapide

1. **Jours 1–2 :** N0.1 à N0.3, push manuel de bout en bout et persistance.
2. **Jours 3–5 :** N0.4 à N0.7, moteur, déduplication et navigation depuis le push.
3. **Jours 6–7 :** tests automatiques et appareils physiques : premier plan,
   arrière-plan, fermeture normale, redémarrage, hors ligne, permission refusée,
   token renouvelé et changement de fuseau. Documenter que « Forcer l’arrêt »
   Android peut bloquer les push jusqu’à la réouverture.
4. **Jours 8–10 :** mode silencieux sans envoi pendant au moins 48 h ; comparer
   chaque alerte proposée avec Graph/Radar et corriger faux positifs, retard et
   doublons.
5. **Rollout :** équipe interne → 100 appareils → 1 000 → 10 % → 100 %.
   Attendre 24 h sans régression entre les paliers ; retour immédiat au palier
   précédent via kill switch.

### Gate GO production

- p95 du job inférieur à 60 s et push synthétique reçu en moins de 2 minutes ;
- moins de 0,1 % de doublons et moins de 1 % d’échecs définitifs d’envoi ;
- zéro token, identifiant brut ou coordonnée précise dans les logs ;
- test fermé Android/iPhone validé avec l’app retirée des applications récentes ;
- coût projeté à 50 000 appareils inférieur à 25 €/mois pour les alertes ;
- contrat/licence fournisseur compatible avec une application publique.

### Après le lancement seulement

- plusieurs lieux et alertes Premium ;
- Redis, plusieurs workers d’alertes et haute disponibilité ;
- personnalisation avancée et historique de notifications ;
- augmentation des fréquences ou des quotas au-delà des mesures réelles.

## État d’implémentation — lots 1 à 3

Mis à jour le 23 août 2026.

- **P0.1 — implémenté** : Radar monté hors écran derrière Graph pour préchauffer le premier viewport ; autoplay déclenché automatiquement à l’ouverture de Radar, mais seulement après la première PNG décodable ; boucle continue à 1,5 s jusqu’à une Pause explicite de l’utilisateur ; frame courante prioritaire ; debounce après pan de 300 ms ; quatre tuiles centrales maximum avec deux requêtes simultanées ; rendu dès la première PNG valide sans attendre le lot.
- **P0.2 — implémenté dans le code** : `RADAR_PROVIDER` explicite ; `PUBLIC_BASE_URL` public HTTPS obligatoire en production ; rejet des adresses loopback/privées ; le mode direct LibreWXR utilise l’origine configurée et jamais le `host` loopback des métadonnées.
- **P0.3 — implémenté dans le code** : palette unifiée sur `13/1_0` dans le backend, staging et production ; conservation des placeholders bruts `{frame}/{z}/{x}/{y}` (ils étaient auparavant encodés en `%7B…%7D`) ; test du proxy vérifiant URL origine, HTTP 200, `image/png` et signature PNG ajouté.
- **P0.4 — implémenté dans le code** : nouvelle route `GET /v1/radar/point-nowcast` reliée à l’outil LibreWXR `get_precip_nowcast` ; cache court par coordonnées (2 minutes, repli périmé 30 minutes) sans consommation du quota de sessions ; injection des six valeurs +60 min dans les frames `nowcast` du graphe ; budget mobile strict de 1,2 s et repli transparent sur Open-Meteo. Le point optionnel ne peut plus retarder l’affichage Radar jusqu’à 8 s.
- **P0.5 — implémenté pour la bêta** : `GET /frames` et ses refresh ne consomment plus de session ; `POST /v1/radar/sessions` est déclenché uniquement lors d'une vraie entrée utilisateur dans Radar ; identifiants d'installation et de session obligatoires ; retries idempotents en mémoire et via compteur partagé ; plan Free/Premium envoyé ; compteur serveur resynchronisé dans l'app. `RADAR_QUOTA_ENFORCED=false` mesure sans bloquer jusqu'à la validation serveur des achats.
- **P0.6 — implémenté sur Android** : cache de tuiles vidé par un gate de compilation réservé au test ; attente d'une image décodée ; maintien de la couche PNG pendant quatre déplacements ; zoom 7→10 ; cycle d'animation complet à 1,5 s ; sonde HTTP déterministe vérifiant 502 puis récupération immédiate. Le dernier APK a été installé et lancé sur le téléphone Android USB ; la sonde réelle a confirmé le retour 502→200 de l’origine.
- **Graph continu — corrigé** : la ligne reste tracée pendant les périodes sèches, atteint exactement la borne 2 h/24 h par interpolation et reprend les données Open-Meteo après la fenêtre LibreWXR +60 min. Ce comportement est identique pour Free et Premium.
- **Chronologie Radar réelle + modèle Premium — implémentée** : Free se termine à la dernière frame de nowcast radar (environ +60 min). Chetiwa+ peut prolonger l'animation jusqu'à +120 min avec six tuiles distinctement étiquetées `prévision modèle`. La seconde heure est protégée par `PREMIUM_RADAR_MODEL_ENABLED`, l'entitlement store et un segment verrouillé dans la timeline ; aucune tuile modèle n'est présentée comme une observation radar.
- **Débit des tuiles — corrigé** : les tuiles Radar utilisent désormais un bucket séparé de 600 requêtes/minute ; elles ne peuvent plus épuiser la limite JSON générale de 120/minute et bloquer météo, recherche ou sessions pendant une animation avec pans/zooms.
- **Déplacement Radar mondial — corrigé** : après un pan manuel, la frame courante précharge d’abord la tuile sous le centre puis trois voisines. La couche reste montée avec les anciennes images et recharge dès la première PNG valide. Un statut compact expose chargement, indisponibilité et relance ; sélectionner le nouveau lieu n’est plus nécessaire.
- **Heure du téléphone — corrigée** : le fuseau du lieu ciblé sert uniquement à décoder correctement les données du fournisseur. Toutes les heures visibles dans Météo, Graph et Radar suivent le fuseau configuré sur le téléphone. Un téléphone réglé sur Paris conserve donc `20:24 · UTC+2` en passant de Paris à Sierra Leone ; les URLs et la frame des tuiles restent attachées au même instant UTC.
- **Crash natif iOS découvert par P0.6 — corrigé** : les builds Profile/Release plantaient au lancement car `GADApplicationIdentifier` était vide. Les profils iOS utilisent maintenant l'identifiant d'application de test officiel Google tant que les publicités réelles restent désactivées.
- **LibreWXR cache — implémenté dans le profil** : budget relevé de 64 à 256 Mo. Le déploiement de ce profil et la mesure `/health` restent à effectuer sur la VM.
- **Tunnel LibreWXR — durci dans le dépôt** : configuration `cloudflared` avec connexions origine persistantes ; sondes locale et publique séparées chaque minute ; trois échecs consécutifs avant action ; redémarrage ciblé LibreWXR ou tunnel ; cooldown de 15 minutes. L’installation du timer sur la VM reste à exécuter.
- **P0 applicatifs — terminés** : restent le déploiement et les contrôles d'exploitation de l'origine/CDN.

P0 — À corriger avant la prochaine build
Priorité	Problème confirmé	Correction minimale
P0.1	Le radar démarre automatiquement, change d’image toutes les 1,1 s, puis lance jusqu’à 24 préchargements dès l’ouverture et après chaque mouvement avec seulement 120 ms de debounce. Les anciens préchargements ne sont pas annulés. Avec une origine lente, les tuiles visibles sont annulées avant d’arriver.	Désactiver l’autoplay initial. Charger d’abord l’image courante. Après 500–700 ms sans mouvement, précharger une seule frame avec 4–8 requêtes maximum et annuler la génération précédente. Ne démarrer l’animation qu’après disponibilité des tuiles. Voir [radar_pane.dart (line 101)](/Users/DEV/Documents/IDEAS/chetiwa/lib/features/radar/presentation/widgets/radar_pane.dart:101), [radar_tile_cache.dart (line 109)](/Users/DEV/Documents/IDEAS/chetiwa/lib/features/radar/data/cache/radar_tile_cache.dart:109) et [radar_bloc.dart (line 443)](/Users/DEV/Documents/IDEAS/chetiwa/lib/features/radar/application/radar_bloc.dart:443).
P0.2	Le backend reconnaît LibreWXR uniquement si le domaine finit par librewxr.net. radar.ezplatforms.com est donc classé comme fournisseur générique. Sans PUBLIC_BASE_URL, il renvoie le host LibreWXR actuel, qui vaut http://127.0.0.1:8080 : URL inutilisable sur un téléphone.	Ajouter un type fournisseur explicite RADAR_PROVIDER=librewxr, rendre PUBLIC_BASE_URL obligatoire en production et refuser le démarrage si les URLs de tuiles sont privées/loopback. Voir [provider_gateway.dart (line 158)](/Users/DEV/Documents/IDEAS/chetiwa/backend/lib/src/provider_gateway.dart:158) et [production.env.example (line 13)](/Users/DEV/Documents/IDEAS/chetiwa/backend/deploy/environments/production.env.example:13).
P0.3	La configuration de palette est contradictoire : production utilise 10/1_1, le runbook 13/1_0, l’app directe choisit 13/1_0.	Utiliser partout 13/1_0, puis ajouter un test HTTP vérifiant 200, image/png et une image décodable. Voir [librewxr-hetzner-runbook.md (line 54)](/Users/DEV/Documents/IDEAS/chetiwa/docs/backend/librewxr-hetzner-runbook.md:54).
P0.4	Graph ↔ Radar n’était pas réellement aligné en production : le backend ne récupérait aucun échantillon MCP `pointRainRateMmPerHour`.	**Corrigé dans le code** : `/v1/radar/point-nowcast`, cache court par coordonnées et injection des six valeurs LibreWXR +60 min dans Graph, avec repli Open-Meteo. La validation finale sur appareil reste couverte par P0.6. Voir [radar_nowcast_alignment.dart (line 9)](/Users/DEV/Documents/IDEAS/chetiwa/lib/features/forecast/domain/services/radar_nowcast_alignment.dart:9).
P0.5	Les quotas pouvaient couper le radar par erreur : chaque refresh était compté comme une session.	**Corrigé pour la bêta** : ouverture explicite et idempotente, refresh gratuits, plan transmis et blocage désactivé par configuration. L'activation future du blocage payant exige toujours une validation d'achat côté serveur ; un header client seul n'est pas une authentification. Voir [app.dart](/Users/DEV/Documents/IDEAS/chetiwa/backend/lib/src/app.dart) et [usage_quota_controller.dart](/Users/DEV/Documents/IDEAS/chetiwa/lib/features/monetization/application/usage_quota_controller.dart).
P0.6	Le smoke test considérait auparavant le Radar fonctionnel dès que l’heure était affichée.	**Corrigé pour Android** : cache froid, tuile PNG réelle, couche conservée pendant quatre pans, zoom 7→10, animation et sonde 502→200. Le dernier passage physique doit être rejoué après autorisation d'installation sur le téléphone. Voir [backend_proxy_smoke_test.dart](/Users/DEV/Documents/IDEAS/chetiwa/integration_test/backend_proxy_smoke_test.dart).


État LibreWXR observé
Le 23 août 2026, l’endpoint de santé indiquait :
- 1 seul worker ;
- cache de 64 Mo presque saturé ;
- taux de hit interne d’environ 5 % ;
- latence moyenne historique d’environ 23,2 s par tuile ;
- seulement 6 observations, soit environ 50 minutes d’historique ;
- uptime d’environ 4 heures ;
- limite conteneur observée de 3,5 Go, alors que le dépôt prévoit 6 Go.
  Les tuiles déjà chaudes ont répondu entre 0,1 et 1 seconde et Cloudflare a bien renvoyé CF-Cache-Status: HIT. Le CDN fonctionne donc sur les URLs testées, mais les nouvelles zones et nouvelles frames restent dépendantes du tunnel et du worker unique. Une panne du tunnel ne rend pas toutes les tuiles immédiatement indisponibles, mais elle met bien la capacité des cold misses et métadonnées à zéro.
  Avant lancement :
- aligner la mémoire réellement déployée avec le profil versionné ;
- augmenter le cache LibreWXR de 64 à au moins 256 Mo, puis mesurer ;
- garantir une règle Cloudflare sur /v2/radar/* avec clé complète frame/z/x/y/palette ;
- ajouter surveillance /health, redémarrage automatique et alerte 5xx ;
- exiger p95 < 2 s sur une tuile froide et < 500 ms sur une tuile CDN avant validation.
  La version LibreWXR épinglée supporte le mode multi, mais sa propre documentation le réserve aux machines de 8 cœurs ou plus. Ne pas activer ses 16 workers par défaut sur la VM actuelle : augmenter d’abord la VM et configurer explicitement 2–4 workers.
  Ce qui peut attendre
- Historique radar 24 h : non disponible. À 10 minutes par frame, il faut environ 144 observations, pas 24. Le serveur n’en conserve que 6. Ne pas le bloquer pour la bêta ; masquer toute promesse 24 h/6 h.
- Redis peut attendre. Firestore reste inutile pour les quotas Radar de la bêta,
  mais devient obligatoire pour la persistance des alertes distantes en N0.3.
- Réplication haute disponibilité : recommandée avant SLA public, mais pas nécessaire pour une bêta contrôlée.
- Cache mobile durable : les tuiles sont actuellement dans Directory.systemTemp, donc purgeables. Migrer vers le répertoire cache de l’application après les P0.
- Historique/stockage persistant LibreWXR : nécessaire plus tard pour 24 h et continuité inter-redémarrage.
Validation
- `flutter analyze` : réussi.
- Tests Flutter : 124/124 réussis.
- Build Android debug : réussi (`build/app/outputs/flutter-apk/app-debug.apk`).
- Tests backend : 49/49 réussis.
- APK Android debug : installation directe USB et lancement réussis ; le smoke réseau complet reste dépendant du retour de `radar.ezplatforms.com` en 200.
- `dart analyze` backend : réussi.
- Smoke test proxy/Radar réel : réussi sur iPhone 16 Pro Max / iOS 26.6, build Profile, backend Chetiwa local joignable sur LAN, fallback direct désactivé, 1 min 03 s.
- Build iOS Profile signée : réussie ; crash natif AdMob corrigé.
- Les modifications des lots 1 à 3 sont présentes dans le worktree et ne sont pas encore déployées.
  Conclusion : les P0 applicatifs sont terminés. Déployer les profils versionnés, mesurer l'origine froide et le CDN, puis limiter la première bêta ; Redis, historique 24 h et haute disponibilité peuvent attendre.
