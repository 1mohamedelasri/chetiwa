# Scénarios météo de référence

Ces scénarios constituent le contrat de cohérence entre Weather Brief, Graph,
Radar et Prévisions. Ils sont reproductibles avec une horloge fixe et ne
dépendent d’aucun appel réseau.

## Échelle de pluie commune

| Classe | Débit en mm/h | Bande visuelle normalisée |
| --- | ---: | ---: |
| Aucune | `< 0,05` | `0 %` |
| Faible | `0,05 à < 0,5` | `0 à 24 %` |
| Modérée | `0,5 à < 4` | `24 à 56 %` |
| Forte | `>= 4` | `56 à 100 %` |

La normalisation est absolue et plafonnée à `12 mm/h`. Elle ne dépend jamais
du maximum de la fenêtre affichée. Une bruine reste donc faible même si elle
est le seul épisode visible.

## Matrice de validation

| Scénario | Fixture | Brief attendu | Intensité maximale | Fenêtres |
| --- | --- | --- | --- | ---: |
| Sec | `dry.json` | Sec | Aucune | 0 |
| Pluie faible | `light_rain_reference.json` | Pluie en cours | Faible | 1 |
| Pluie modérée | `moderate_rain.json` | Pluie en cours | Modérée | 1 |
| Pluie forte | `heavy_rain.json` | Pluie en cours | Forte | 1 |
| Épisodes multiples | `multiple_showers.json` | Plusieurs épisodes | Modérée | 2 |

Les tests automatiques vérifient pour chaque scénario :

- le classement de chaque point par l’échelle commune ;
- le résumé et le nombre de fenêtres calculés depuis les points bruts ;
- l’intensité maximale exposée par Graph ;
- l’intensité appliquée au calque Radar de continuité.

## Validation visuelle automatisée

La suite d’intégration `reference_weather_visual_test.dart` injecte les mêmes
fixtures avec l’horloge fixe du 20 août 2026 à 12:00 UTC. Elle ouvre Graph,
Radar et Prévisions, vérifie les éléments structurants et capture chaque écran
en portrait.

| Plateforme | Sec | Faible | Modérée | Forte | Épisodes multiples |
|---|---:|---:|---:|---:|---:|
| Android Emulator | 3 écrans | 3 écrans | 3 écrans | 3 écrans | 3 écrans |
| iOS Simulator | 3 écrans | 3 écrans | 3 écrans | 3 écrans | 3 écrans |

Les 30 preuves sont archivées dans [`screenshots`](screenshots). Les commandes
reproductibles sont :

```sh
flutter drive \
  --driver=test_driver/visual_validation_driver.dart \
  --target=integration_test/reference_weather_visual_test.dart \
  -d <android-device>

LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter drive \
  --driver=test_driver/visual_validation_driver.dart \
  --target=integration_test/reference_weather_visual_test.dart \
  -d <ios-device>
```

Cette validation a notamment permis de corriger les contrastes des métriques et
de la carte météo sur surface sombre, puis d’aligner le calque Radar de
continuité sur la palette gris → orange → rouge. Le scénario sec n’affiche
aucun faux écho ; les niveaux faible, modéré et fort restent visuellement
distincts.

## Neige et précipitations mixtes

Le modèle de domaine actuel décrit une intensité de précipitation liquide. Le
flux de tuiles Radar actuellement branché ne fournit pas séparément le type
d’hydrométéore au niveau de la tuile. Chetiwa ne doit donc pas inventer une
classification neige/mixte à partir d’une couleur.

Avant d’ajouter ces scénarios, il faudra :

1. sélectionner un fournisseur qui expose explicitement pluie, neige, grésil
   ou mixte ;
2. ajouter le type de précipitation au modèle de domaine ;
3. définir une palette accessible distincte de l’intensité ;
4. ajouter les fixtures et les mêmes contrôles de cohérence multi-écrans.
