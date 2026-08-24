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

Les tuiles de fond ne passent pas par LibreWXR : chaque téléphone appelle
directement CARTO ou Esri. Augmenter la VM ne change donc rien à leur capacité.

- CARTO raster demande désormais une clé, offre un fair use de 5 M de
  tuiles/mois et peut exiger un accord commercial. Les URLs actuelles sans clé
  ne sont pas un choix de production durable.
- ArcGIS Location Platform exige un compte/jeton. Le tarif publié inclut 2 M de
  tuiles/mois, puis 0,15 USD par 1 000 tuiles, ou un modèle par session.
- Le satellite ne doit pas rester le fond par défaut à grande échelle avant
  calcul du coût. À 12 tuiles par ouverture quotidienne, 50 000 DAU représentent
  déjà environ 18 M de tuiles/mois.

Avant la sortie publique, choisir explicitement : contrat CARTO/Esri avec clé
et budget, ou fond vectoriel/PMTiles auto-hébergé. Les attributions visibles ne
remplacent pas le droit commercial.

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
