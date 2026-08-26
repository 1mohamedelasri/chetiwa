# Capacité et supervision météo/radar — 25 août 2026

## Verdict actuel

Le profil 4 Gio a été déployé le 24 août 2026 à 22:38 UTC après identification
de 25 redémarrages du conteneur et de plusieurs `oom-kill`. La cause directe
des `502` était l'origine LibreWXR tuée à sa limite de 3 Gio, pas une panne du
Tunnel Cloudflare. Le préchauffage soumettait jusqu'à 35 076 tuiles après un
cycle et amplifiait la pression mémoire.

Après correction : aucun redémarrage, aucun OOM, environ 678 Mio au repos,
cache tuiles borné à 256 Mo, préchauffage désactivé et watchdog sain. Le pic du
démarrage a atteint 2,9 Gio et 321 Mio de swap ; la VM 4 Gio reste donc un
profil de lancement minimal, pas la cible définitive de montée en charge.

La capacité LibreWXR ne doit pas être exprimée comme un nombre fixe
d'installations. Elle dépend des tuiles demandées par session, de la dispersion
géographique et surtout du taux de HIT Cloudflare. Le benchmark public borné du
25 août a mesuré 12 tuiles européennes avec quatre requêtes simultanées :

| Mesure | Résultat |
| --- | ---: |
| Tuiles valides | 12/12 |
| Cloudflare MISS | 11 |
| p50 | 519 ms |
| p95 | 673 ms |
| Débit mesuré à concurrence 4 | 5,94 tuiles/s |

Le contrôle post-déploiement sur Paris, Freetown, New York, Tokyo et Sydney a
mesuré les MISS entre 122 et 502 ms et les HIT entre 36 et 43 ms. Le benchmark
post-déploiement de 12 tuiles a donné p50 574 ms, p95 641 ms et 6,24 tuiles/s.

## Stress test borné du 24 août 2026

Le script [`stress-test-public-radar.sh`](../../deploy/librewxr/stress-test-public-radar.sh)
a demandé 288 tuiles froides uniques, par paliers de 48, sans erreur, OOM ou
restart :

| Concurrence | p50 | p95 | Débit observé |
| ---: | ---: | ---: | ---: |
| 1 | 216 ms | 297 ms | 1,37 tuile/s |
| 2 | 361 ms | 534 ms | 5,33 tuiles/s |
| 4 | 529 ms | 723 ms | 6,00 tuiles/s |
| 8 | 756 ms | 1,16 s | 8,00 tuiles/s |
| 12 | 1,23 s | 1,68 s | 8,00 tuiles/s |
| 16 | 1,75 s | 2,33 s | 6,86 tuiles/s |

La saturation commence après huit requêtes froides simultanées : ajouter de la
concurrence augmente ensuite la latence sans augmenter le débit. Le test a
commencé pendant le cycle RRQPE/nowcast de 22:50 ; la toute première tuile a
mis 22,6 s alors que le p95 du palier est resté à 297 ms. Ce cas extrême
confirme que les deux vCPU sont le goulot pendant la collecte, même si
Cloudflare masque normalement ce coût pour les tuiles déjà demandées.

La planification conserve donc seulement **3 tuiles origine/s continues**,
moins de la moitié du maximum de burst, afin de laisser de la CPU aux cycles
météo. Avec deux sessions Radar/jour, 96 tentatives par animation et 15 % du
trafic quotidien dans l'heure de pointe :

| HIT CDN/mobile | Radar simultanés prudents | DAU prudents |
| ---: | ---: | ---: |
| 80 % | 9 | ~1 900 |
| 90 % | 19 | ~3 750 |
| 95 % | 38 | ~7 500 |

Décision de rollout : zone verte jusqu'à 2 000 DAU ; surveillance renforcée
entre 2 000 et 4 000 ; passer à au moins 4 vCPU/8 Gio avant 5 000 DAU, ou plus
tôt si le HIT réel reste sous 90 %, si le p95 MISS dépasse 2 s ou si les cycles
de calcul provoquent des attentes visibles. À 50 000 DAU, prévoir le profil
multi-worker 8+ vCPU/32 Gio et une architecture redondante ; la VM actuelle ne
suffit pas.

Pour la planification, Chetiwa ne consomme que **3 tuiles origine/s** — 50 %
du débit observé — afin de garder de la marge pour les cycles de collecte,
les point-nowcasts et les variations réseau.

Une première animation peut demander environ 12 frames × 8 tuiles visibles,
soit 96 tentatives réseau avant cache disque. Avec deux sessions Radar par
utilisateur actif et 15 % des sessions quotidiennes concentrées dans l'heure de
pointe, l'enveloppe prudente est :

| HIT CDN/mobile | Tuiles origine/session | Sessions Radar simultanées d'une minute | DAU prudents |
| ---: | ---: | ---: | ---: |
| 80 % | 19,2 | 9 | ~1 900 |
| 90 % | 9,6 | 19 | ~3 800 |
| 95 % | 4,8 | 38 | ~7 500 |
| 0 % | 96 | 2 | ~375 |

Ce tableau est une estimation de capacité, pas un SLA. Après production, la
valeur autoritative sera calculée avec les vraies métriques
`uniqueTilesPerSession`, le taux de HIT Cloudflare et la répartition horaire.
Avant sept jours de trafic réel, retenir **2 000–5 000 DAU** comme enveloppe de
bêta, avec rollout progressif. Le cache 256 Mo doit être déployé avant ce test.

## Autres fournisseurs : limites indépendantes de la VM

### Open-Meteo

Le service gratuit est non commercial et limité à 600 appels/minute,
5 000/heure, 10 000/jour et 300 000/mois. Il ne convient donc pas à une
publication commerciale, quel que soit le nombre de serveurs Chetiwa.

Le plan Standard couvre 1 M d'appels/mois, Professional 5 M. La requête Chetiwa
contient 18 variables ; Open-Meteo peut la compter fractionnellement au-delà
d'un appel. En prenant 1,8 unité par rafraîchissement :

- Standard : environ 9 000 DAU à deux rafraîchissements/jour ;
- Professional : environ 46 000 DAU à deux rafraîchissements/jour ;
- à 50 000 DAU : optimiser le cache et mesurer, puis prévoir Professional avec
  marge ou un contrat supérieur.

### Fond de carte

Le fond ne passe pas par LibreWXR : les SDK Google Maps Android/iOS le rendent
directement. Augmenter la VM Hetzner ne change donc rien à sa capacité.

- `MapType.hybrid` est le fond Radar officiel pour tous ; `MapType.normal` reste
  sélectionnable.
- Les clés Android/iOS sont séparées, limitées aux deux SDK et restreintes aux
  identifiants d’application. Aucun Map ID n’est configuré.
- Le logo et les attributions Google restent dans la surface native, au-dessus
  de la timeline.
- Le cache Chetiwa 128 Mo concerne uniquement LibreWXR ; les données Google ne
  sont ni proxyfiées ni stockées par Chetiwa.

Surveiller la page Google Maps Platform, les quotas et les erreurs de clés à
chaque release. Une panne du fond ne doit jamais bloquer Graph ou Prévisions.

## Seuils de scaling LibreWXR

Augmenter ou corriger l'infrastructure lorsqu'un de ces signaux persiste :

| Signal sur 15 minutes | Action |
| --- | --- |
| CPU origine > 70 % | Vérifier le HIT CDN ; augmenter les cœurs si le HIT est déjà > 90 % |
| RAM > 75 % ou OOM/restarts | Passer à 16 Go avant d'augmenter les workers |
| MISS p95 > 2 s sur 3 benchmarks | Examiner cache/collecte, puis CPU et disque |
| HIT p95 > 500 ms | Incident CDN/tunnel/réseau, pas un manque de RAM LibreWXR |
| HIT Cloudflare < 90 % | Corriger Cache Rules/clé complète frame-z-x-y-palette |
| 5xx > 1 % pendant 5 min | Geler le rollout et analyser Origin Analytics |
| 3 sondes metadata échouées | Le watchdog redémarre uniquement origine ou tunnel |
| > 40 sessions Radar simultanées prévues | Rejouer le benchmark concurrence 4/8 avant rollout |

Ne pas activer le profil LibreWXR `multi` sur la petite VM. Commencer par cache
256 Mo, mesures, puis VM 8+ cœurs/32 Go si plusieurs workers deviennent
nécessaires. Une seconde origine exige un cache partagé et un répartiteur.

## Exploitation

Déployer le profil versionné et le watchdog depuis un poste autorisé :

```bash
deploy/librewxr/deploy-production-profile.sh root@116.203.124.254
```

Le script vérifie la VM 4 Gio, crée un swap de sécurité de 2 Gio si nécessaire,
sauvegarde `.env`, valide Compose, applique le cache 256 Mo, désactive le
préchauffage massif, installe le timer et restaure automatiquement le profil
précédent si les sondes échouent.

Vérifier la surface publique depuis n'importe quelle région :

```bash
CHETIWA_PROBE_REGION=paris deploy/librewxr/probe-public-radar.sh
deploy/librewxr/benchmark-public-radar.sh
```

Le stress test est volontairement plafonné à 16 requêtes simultanées et 64
tuiles par palier :

```bash
deploy/librewxr/stress-test-public-radar.sh
```

Créer la sonde Google Cloud depuis Europe, USA et Asie :

```bash
deploy/librewxr/provision-public-observability.sh \
  GCP_PROJECT_ID OPTIONAL_NOTIFICATION_CHANNEL_ID
```

Le workflow `librewxr-monitor.yml` rejoue aussi la sonde publique chaque heure,
afin de borner les minutes GitHub Actions. Les échecs apparaissent dans GitHub Actions et déclenchent les
notifications GitHub configurées pour le dépôt.

Dans Cloudflare, activer **Notifications → Origin Error Rate** pour la zone et
filtrer `radar.ezplatforms.com`. Utiliser une sensibilité moyenne au faible
trafic. Consulter **Speed → Origin Analytics** pour p50/p95/p99,
`originResponseStatus`, `edgeResponseStatus`, chemins les plus lents et 5xx.

Enfin, `cloudflared` expose des métriques Prometheus sur son port local
20241–20245 par défaut. Elles permettent de suivre connexions tunnel, RTT,
reconnexions, goroutines et échecs de scrape sans rendre ce port public.
