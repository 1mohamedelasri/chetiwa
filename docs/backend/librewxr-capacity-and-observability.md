# Capacité et supervision météo/radar — audit du 27 août 2026

## Enregistrement reproductible — 30 septembre 2026

[`capacity-check.py`](../../deploy/librewxr/capacity-check.py) est un outil de
lecture seule, sans dépendance Python externe, pour Linux avec cgroup v2. Il
enregistre l'identité du conteneur, la RAM, le swap, les compteurs noyau, la
pression mémoire/I/O et les horodatages des quatre observations et six
prévisions. Les seuls appels Docker sont `inspect` et `logs`; aucun déploiement,
rafraîchissement forcé, changement de limite ou test de charge n'est exécuté.
Il ne lit pas les variables d'environnement. Il conserve uniquement la catégorie
et l'horodatage des événements IFS/nowcast/publication, jamais les logs bruts.

Depuis un poste disposant déjà d'un accès SSH autorisé, recueillir d'abord une
fenêtre de quinze minutes sur la VM actuelle (aucune modification de pare-feu
ou de forfait n'est nécessaire pour cet outil) :

```bash
ssh root@116.203.124.254 'python3 - record --duration 900 --interval 10' \
  < deploy/librewxr/capacity-check.py \
  > tmp/production-audit/capacity-2026-09-30.jsonl
```

Puis contrôler le fichier local en déclarant la limite réellement attendue,
actuellement 3 Gio :

```bash
python3 deploy/librewxr/capacity-check.py assess \
  tmp/production-audit/capacity-2026-09-30.jsonl --expected-radar-mib 3072
```

Le code de sortie est **1** pour une pression mesurée, **2** pour des éléments
manquants et **0** uniquement pour un contrôle mémoire complet et favorable.
Un court enregistrement peut démontrer un échec sans contenir un cycle horaire
IFS; il ne peut pas démontrer une réussite sans ce cycle. Après un correctif,
utiliser une nouvelle fenêtre de 4 800 secondes (`--duration 4800`, valeur par
défaut) et vérifier les phases réellement observées. Une durée seule ne suffit
pas : il faut un nouveau fetch IFS terminé, les six nowcasts, une publication
complète dont les horodatages avancent et au moins 60 secondes de stabilisation.

Pendant la régénération, une nouvelle observation peut faire expirer la première
ancienne prévision : le serveur expose alors brièvement quatre observations et
cinq prévisions. Le rapport distingue ces transitions des publications terminées.
Il tolère uniquement une séquence alignée à dix minutes, sans changement de
contenu au milieu de la transition, rétablie à six prévisions dans une borne
conservatrice de 120 secondes (intervalle d'échantillonnage compris). La
publication terminée et les 60 dernières secondes de stabilisation doivent
contenir les quatre observations et six prévisions alignées. Une fenêtre
persistante, malformée ou non rétablie reste incomplète. Les anomalies de
métadonnées ne suppriment jamais les mesures noyau valides : une pression mémoire
avérée reste un échec même si la couverture des frames est insuffisante.

Le contrôle refuse les redémarrages, les resets de compteurs, les interruptions,
les données absentes et les fenêtres incomplètes. Les seuils conservateurs
locaux de dépistage sont : aucun nouvel événement `high`/`max`/OOM, RAM radar
échantillonnée au plus à 90 % de sa limite, au moins 512 Mio de RAM hôte
disponible, croissance du swap radar au plus 64 Mio, I/O swap hôte p95 au plus
1 Mio/s, pression mémoire `some avg10` au plus 5 % au pic et 1 % au p95. Les
pics historiques du noyau sont rapportés séparément; ils ne prouvent pas une
pression nouvelle. Les valeurs de swap et de PSI hôte concernent tous les
services, pas seulement le radar.

Ces seuils sont un filtre de diagnostic, pas un SLA ni une garantie de débit.
La marge après les limites radar/API est informative; le budget proposé pour
une VM plus grande n'impose pas une augmentation de forfait à la VM actuelle.
Tout résultat conserve `productionReady: false` : il faut encore vérifier
l'inventaire réel des services, la stabilité des pics et du régime établi,
puis corréler les mesures avec des lectures API/tuiles concurrentes bornées.
La suite hors réseau est disponible via
`python3 deploy/librewxr/capacity-check-test.py`.

## Contrôle mémoire noyau — 19 septembre 2026

L'audit a constaté un écart de supervision : la courbe Netdata
`cgroup_librewxr-librewxr-1.mem_usage` affichait zéro swap alors que le noyau
mesurait plus de 1 Gio dans `memory.swap.current`. Pour décider d'un correctif
ou d'un changement de capacité, vérifier directement le cgroup v2 du conteneur.
Les commandes suivantes sont en lecture seule, à exécuter sur l'origine :

```bash
radar_pid=$(docker inspect --format '{{.State.Pid}}' librewxr-librewxr-1)
radar_cgroup=$(awk -F: '$1 == "0" { print $3 }' "/proc/$radar_pid/cgroup")
radar_cgroup_dir="/sys/fs/cgroup$radar_cgroup"
for radar_metric in memory.current memory.max memory.peak memory.swap.current \
  memory.events memory.pressure io.pressure; do
  printf '%s\n' "$radar_metric"
  cat "$radar_cgroup_dir/$radar_metric"
done
vmstat 1 5
```

Les valeurs `memory.*` simples sont en octets. `memory.events` contient des
compteurs : `max` signale une rencontre avec la limite, `oom` et `oom_kill`
signalent les échecs d'allocation et les processus tués. `memory.pressure`
donne les pourcentages de temps bloqué sur 10/60/300 secondes et un total
cumulé en microsecondes. Les colonnes `si`/`so` de `vmstat` mesurent les échanges
swap du serveur entier, pas seulement ceux de LibreWXR.

Relever les compteurs avant et après une publication complète du radar et de
ses prévisions, avec le même conteneur et sans compilation concurrente.
Comparer les **deltas**, le swap actif, les échanges swap et la pression ; un
pic historique ou des pages froides en swap ne suffisent pas à établir une
latence actuelle. Un redémarrage recrée le cgroup et remet ses compteurs à
zéro : relancer la résolution du PID/chemin et conserver une nouvelle base de
mesure. Ne pas conclure à une amélioration en comparant deux totaux de durées
différentes. Les correctifs de grilles float32 puis d'axes creux réduisent les
allocations sans changer les pixels, la couverture ou la durée des prévisions ;
ils ne constituent pas une garantie d'absence de pression sur cette VM.


Le 19 septembre, les trois correctifs (coordonnées float32, axes creux,
remappage par blocs de 512 lignes) ont été déployés sans réduire les régions,
la résolution ou les six prévisions. Une publication naturelle complète,
mesurée de 11:50:17 à 12:04:26 UTC avec 60 secondes de stabilisation, a encore
ajouté **931 événements de limite mémoire**, sans OOM, avec un swap passant de
54 à 866 Mio. La pression noyau `avg10` a atteint 19,55 %. Ce cycle comprenait
également un rafraîchissement ECMWF IFS : il ne permet pas de classer les
performances des versions à partir d'un seul cycle différent. Les correctifs
réduisent des allocations vérifiées, mais la marge mémoire reste insuffisamment
validée avant une ouverture publique. Une hausse de capacité payante ou une
réduction supplémentaire des allocations doit être décidée et mesurée ; ne pas
augmenter simplement la limite du conteneur sur cet hôte d'environ 3,8 Gio.

## Protection du stockage déployée le 29 août 2026

L'incident `no space left on device` venait notamment de memmaps RRQPE
persistants que le processus suivant ne rechargeait pas et ne pouvait donc
jamais évincer. Le correctif de démarrage supprime uniquement ces fichiers
fetch-side devenus inaccessibles avant de reconstruire la fenêtre récente. Lors
du premier déploiement, 81 fichiers représentant 2 259,5 Mio ont été retirés ;
le volume LibreWXR est passé d'environ 3,6 Gio à 1,3 Gio et l'utilisation de la
racine de 31 % à 22 %.

`chetiwa-storage-guard.timer` contrôle toutes les cinq minutes :

- disque et inodes : avertissement 70 %, critique 85 %, urgence 90 % ;
- RRQPE : avertissement 512 Mio, critique 1 Gio ;
- couche Docker LibreWXR : avertissement 1,5 Gio, critique 2,5 Gio.

La dernière mesure est lisible sans outil externe :

```bash
cat /var/lib/chetiwa-storage-guard/status.env
systemctl status chetiwa-storage-guard.timer
journalctl -u chetiwa-storage-guard.service -n 30 --no-pager
```

Le service ne supprime jamais automatiquement une donnée active. Pour recevoir
les changements d'état hors du serveur, connecter un agent de supervision tel
que Netdata Cloud puis router les alertes `disk.space`, `disk.inodes` et l'état
systemd de la garde vers l'e-mail ou le canal d'astreinte retenu.

Les trois conteneurs utilisent aussi `json-file` avec `max-size=10m` et
`max-file=3`. Si le tunnel a été créé manuellement sans ces limites, appliquer :

```bash
deploy/librewxr/recreate-cloudflared-bounded-logs.sh root@116.203.124.254
```

## Audit de latence et correctifs de production

Le ralentissement n'avait pas une cause unique. Le chemin complet a été mesuré
et corrigé du téléphone jusqu'à LibreWXR :

| Cause confirmée | Effet utilisateur | Correction |
| --- | --- | --- |
| URL API sans suffixe statique | Cloudflare répondait `DYNAMIC` et chaque téléphone revenait à l'origine | URL canonique `.png`; HIT Cloudflare vérifié |
| API → origine via Tunnel public | Double trajet Cloudflare/Tunnel sur chaque MISS | réseau Docker interne `librewxr:8080` |
| Trois essais origine de 10 s | une tuile lente pouvait durer 30 s | un essai borné à 7 s, dernier visuel conservé |
| Requêtes froides identiques concurrentes | plusieurs rendus identiques consommaient le CPU | single-flight dans le cache API |
| Limite partagée par IP mobile | plusieurs utilisateurs derrière le même NAT pouvaient se bloquer | identifiant d'installation anonyme sur chaque requête tuile |
| Six requêtes d'un ancien viewport | après un pan/zoom, la nouvelle ville attendait jusqu'à 8 s | annulation du client HTTP et priorité immédiate au nouveau viewport |
| Timer Radar actif pendant la veille | curseur et couche pouvaient reprendre sur deux frames différentes | suspension/reprise atomique du BLoC et du playhead |
| Loader recréé après une longue veille | écran de préparation alors qu'une carte valide existait | conservation de la dernière surface fiable; restauration silencieuse |
| Cache disque mobile taillé seulement au lancement | croissance et I/O au cours d'une longue session | taille contrôlée périodiquement après 64 écritures |
| Cache tuiles/coordonnées origine trop petit | évictions et régénérations fréquentes | 256 Mo tuiles, 512 Mo coordonnées |
| Préchauffage limité à Paris z7 | USA et changements de zoom restaient froids | Paris + Nashville en z5/z7/z9, 96 couples frame/cible |
| Démarrage bloqué par ECMWF/nowcast | plusieurs minutes d'indisponibilité après un déploiement | frames restaurées servies immédiatement; recalcul en arrière-plan |
| Écriture memmap sous le verrou de lecture | les tuiles froides attendaient jusqu'à 30 s pendant un cycle de collecte | lectures sur snapshot atomique non bloquantes; l'ancien frame reste servi pendant l'écriture |
| Exécuteur mono-thread partagé avec l'ingestion | le calcul d'une tuile visible restait en file derrière ECMWF/GRIB malgré un `/health` vert | pools dédiés au calcul géométrique et à l'encodage des tuiles interactives |

Mesures du 27 août après correction :

| Chemin | Résultat |
| --- | ---: |
| Tuile API avec HIT Cloudflare, 5 essais | 39–48 ms |
| 12 tuiles origine froides, concurrence 4 | p50 649 ms, p95 736 ms |
| Réponses invalides pendant le benchmark | 0/12 |
| Préchauffage Europe + CONUS | 96/96 |
| 4 MISS origine pendant une collecte à 118 % CPU | 160–314 ms |
| 16 tuiles origine, concurrence 4, pendant la collecte | maximum 592 ms, 0 erreur |
| 16 tuiles CONUS pendant un pic à 198 % CPU | maximum 513 ms, 0 erreur |
| MISS API publique puis HIT Cloudflare | 304 ms puis 39–40 ms |

Un « 100 % sans lag » n'est pas un SLA techniquement honnête sur réseau
mobile. La cible de release est : aucune interface bloquée par le réseau,
aucun ancien viewport prioritaire, dernier radar valide toujours conservé,
HIT p95 < 500 ms, MISS p95 < 2 s et 5xx < 1 %.

## Verdict actuel

Le profil 4 Gio a été déployé le 24 août 2026 à 22:38 UTC après identification
de 25 redémarrages du conteneur et de plusieurs `oom-kill`. La cause directe
des `502` était l'origine LibreWXR tuée à sa limite de 3 Gio, pas une panne du
Tunnel Cloudflare. Le préchauffage soumettait jusqu'à 35 076 tuiles après un
cycle et amplifiait la pression mémoire.

Après correction : aucun redémarrage, aucun OOM, environ 678 Mio au repos,
cache tuiles borné à 256 Mo, préchauffage mondial désactivé, préchauffage ciblé
Europe/CONUS actif et watchdog sain. Le pic du
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
concurrence augmente ensuite la latence sans augmenter le débit. Le test
initial avait commencé pendant le cycle RRQPE/nowcast de 22:50 ; sa première
tuile avait mis 22,6 s. L'audit a relié ce cas à la file mono-thread partagée
entre ingestion et rendu. Après isolation du chemin interactif, un retest
effectué pendant une collecte à 118 % CPU a servi 16 tuiles avec quatre
requêtes simultanées en 2–592 ms, sans erreur. Les deux vCPU restent une limite
de débit, mais une collecte ne bloque plus une tuile visible.

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
bêta, avec rollout progressif. Le cache 256 Mo est déployé.

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
