# Profil Android physique — 24 août 2026

Appareil : Xiaomi M2011K2G, Android physique USB, build Flutter `profile`,
Impeller/Vulkan. Les statistiques Firebase sont restées désactivées.

## Démarrage froid

Trois lancements après `am force-stop`, mesurés avec `am start -W` :

- 706 ms ;
- 697 ms ;
- 664 ms ;
- moyenne : **689 ms**.

## Animation Radar stabilisée

Fenêtre de 30 secondes après chargement des tuiles, mesurée avec la VM Timeline.

| Mesure | Avant optimisation | Après optimisation |
| --- | ---: | ---: |
| Thread UI moyen | 12,83 ms | **11,20 ms** |
| Thread UI p95 | 28,34 ms | **23,64 ms** |
| Frames UI > 16,7 ms | 43,9 % | **26,8 %** |
| Raster p95 | 11,72 ms | **12,12 ms** |
| Frames raster > 16,7 ms | 0 % | **0 %** |

La correction remplace les opacités par tuile par une seule couche Radar et
réduit le buffer hors écran de deux anneaux à un. Le dernier anneau est conservé
pour empêcher les trous lors d'un pan court ; la tuile centrale reste
préchargée après un déplacement long.

## Verdict

Le démarrage Android est compatible avec une bêta. L'animation Radar ne bloque
pas le raster ; quelques changements de frame dépassent encore un vsync sur le
thread UI. Ce compromis est acceptable pour la bêta contrôlée car supprimer le
dernier buffer réintroduirait les retards de tuiles en mouvement. Refaire la
même trace sur un Android d'entrée de gamme avant un rollout public à 100 %.
