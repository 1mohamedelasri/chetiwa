# LibreWXR sur Hetzner : profil de lancement minimal

## Décision

L'instance auto-hébergée est l'origine Radar actuellement publiée derrière
Cloudflare Tunnel. Les téléphones utilisent uniquement son URL publique et le
cache CDN ; le port d'origine ne doit pas être exposé directement.

Le serveur de lancement actuel est une VM Hetzner **dédiée à LibreWXR**, avec
2 vCPU et 4 Gio de RAM. Le profil contrôlé réserve 3 Gio au conteneur et crée
2 Gio de swap de sécurité. Pour absorber davantage de trafic ou réactiver le
préchauffage, passer d'abord à 8 Gio de RAM.

## Profil initial

Le fichier [`hetzner-small.env`](../../deploy/librewxr/hetzner-small.env)
active :

- radar OPERA Europe ;
- couche de précipitations mondiale RRQPE/IFS à résolution moindre ;
- nowcast expérimental de 60 minutes ;
- six frames d'historique ;
- ni satellite, ni alertes, ni modèles régionaux lourds.

Le graphe Chetiwa reste la référence explicitement nommée pour la prévision au
point de maintenant à +2 h. Ne pas présenter la couche mondiale RRQPE comme un
radar terrestre là où LibreWXR ne dispose pas de composite radar natif.

## Installation contrôlée

1. Créer une VM Hetzner Ubuntu LTS dédiée, puis installer Docker Engine et
   `cloudflared` selon leurs documentations officielles.
2. Fermer toutes les entrées vers le port 8080. Le fichier de configuration le
   publie uniquement sur `127.0.0.1`.
3. Copier ce dépôt sur la VM et lancer :

   ```sh
   deploy/librewxr/install-on-hetzner.sh
   ```

4. Remplacer `radar.chetiwa.example` dans `/opt/chetiwa/librewxr/.env` par le
   sous-domaine réel, avant le démarrage.
5. Créer un Cloudflare Tunnel vers `http://127.0.0.1:8080`. Ne pas rediriger
   de port depuis le routeur ou exposer l'adresse IP de l'origine.
6. Démarrer et vérifier :

   ```sh
   cd /opt/chetiwa/librewxr
   docker compose up --build -d
   curl --fail http://127.0.0.1:8080/health
   curl --fail https://radar.ezplatforms.com/public/weather-maps.json
   ```

   Les deux sondes sont obligatoires : une origine locale saine accompagnée
   d'un `502` public identifie une panne du tunnel, pas de LibreWXR.

7. Installer le watchdog seulement après réussite des deux sondes :

   ```sh
   sudo deploy/librewxr/install-health-watchdog.sh
   systemctl list-timers chetiwa-radar-watchdog.timer
   journalctl -u chetiwa-radar-watchdog.service -n 50 --no-pager
   ```

   Il attend trois échecs consécutifs. Si l'origine locale tombe, il redémarre
   LibreWXR ; si seule l'URL publique tombe, il redémarre `cloudflared`. Un
   cooldown de quinze minutes empêche toute boucle de redémarrage. Utiliser
   [`cloudflared-config.yml.example`](../../deploy/librewxr/cloudflared-config.yml.example)
   comme base du tunnel nommé, sans committer le fichier de credentials.
   Le service `cloudflared` doit conserver `Restart=on-failure` et
   `RestartSec=5s`. Une vraie haute disponibilité demandera ensuite une
   seconde réplique `cloudflared` sur un autre hôte ; deux services sur la même
   VM ne protègent pas contre la panne de cette VM.

   La sonde automatique utilise le petit document
   `/public/weather-maps.json`, pas `/health` : ce dernier calcule des
   statistiques de cache volumineuses et peut dépasser plusieurs secondes sur
   le worker unique sans que l'origine soit réellement en panne.

   La commande recommandée applique maintenant le profil complet, vérifie la
   RAM, conserve une sauvegarde de `.env` et restaure automatiquement l'ancien
   profil si les sondes échouent :

   ```bash
   deploy/librewxr/deploy-production-profile.sh root@116.203.124.254
   ```

   Pour mettre à niveau une installation existante vers le profil versionné
   (limite conteneur 3 Gio, cache tuiles 256 Mo, préchauffage désactivé et
   watchdog corrigé), lancer depuis le Mac :

   ```sh
   deploy/librewxr/deploy-production-profile.sh root@116.203.124.254
   ```

   Le script recrée uniquement le conteneur LibreWXR avec son `.env`, réinstalle
   le timer et vérifie les métadonnées locales/publiques. Il crée un swap de
   sécurité de 2 Gio s'il n'en existe aucun. Il ne modifie ni les credentials
   Cloudflare, ni le DNS, ni le pare-feu.

8. Changer seulement ces variables dans le runtime du backend Chetiwa :

   ```text
   RADAR_METADATA_URL=https://radar.ezplatforms.com/public/weather-maps.json
   RADAR_TILE_URL_TEMPLATE=https://radar.ezplatforms.com{frame}/256/{z}/{x}/{y}/13/1_0.png
   PUBLIC_BASE_URL=https://api.<domaine>
   ```

L'APK continue d'appeler le backend Chetiwa : elle ne connaît jamais
l'URL privée de l'origine, ni aucun jeton d'infrastructure.

La palette `13` est la LUT Chetiwa gris-vers-rouge appliquée par
`chetiwa-drops-palette.patch`. Elle laisse les faibles échos en gris avec une
opacité progressive et réserve le rouge aux noyaux de précipitation. Le patch
est conservé avec le code de déploiement pour que la modification AGPL reste
reproductible et publiable avec le reste des sources du service.

## Monter en charge

| Signal observé | Action |
| --- | --- |
| Mémoire durablement > 75 %, erreurs de santé ou rendu lent | Passer à 16 Go, garder le mode `single` |
| CPU soutenu > 70 % ou saturation des tuiles | Ajouter CDN/cache devant l'API puis mesurer |
| Plusieurs cœurs durablement nécessaires | Basculer en profil `multi` sur une VM 8+ cœurs / 32 Go |
| Plusieurs instances | Ne pas partager le cache local ; concevoir un stockage/cache partagé et un répartiteur avant d'ajouter une seconde origine |

Le stress test du 24 août 2026 place le plateau de la VM actuelle autour de
8 tuiles froides/s, avec dégradation au-delà de 8–12 requêtes simultanées. Pour
conserver la collecte météo et le nowcast, exploiter au maximum 3 tuiles
origine/s continues. Passer à 4 vCPU/8 Gio avant 5 000 DAU, ou dès 2 000 DAU
si le taux de HIT Cloudflare est inférieur à 90 %.

Le dimensionnement est volontairement contrôlé par des métriques. Il ne faut
pas déclencher une VM plus grande uniquement selon le nombre d'installations :
les tuiles effectivement servies, le taux de cache et les limites CPU/RAM sont
les vrais signaux.

Le profil 4 Gio est acceptable pour le rollout initial uniquement tant que le
taux de HIT CDN reste élevé et qu'aucun OOM ne réapparaît. Le démarrage peut
consommer environ 2,9 Gio et utiliser temporairement le swap pendant le
chargement RRQPE/ECMWF. Une utilisation durable du swap, un redémarrage ou une
RAM supérieure à 75 % impose le passage à 8 Gio avant d'augmenter le trafic.

Le calcul de capacité, la sonde de tuiles, le benchmark borné et la procédure
de supervision multi-régions sont documentés dans
[`librewxr-capacity-and-observability.md`](librewxr-capacity-and-observability.md).
