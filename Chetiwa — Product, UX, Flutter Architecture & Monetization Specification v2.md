# Chetiwa
## Product, UX, Flutter Architecture & Monetization Specification — MVP v2

**Produit :** Chetiwa  
**Plateformes :** iOS + Android  
**Framework :** Flutter / Dart  
**Marché initial :** France  
**Expansion :** Europe, puis Maroc  
**Business model :** Freemium — publicité + Chetiwa+  
**Positionnement :** pluie à court terme, hyper-locale, extrêmement rapide à consulter.

---

# 1. Vision

Chetiwa n'est pas une application météo généraliste.

Elle répond principalement à quatre questions :

**Quand va-t-il pleuvoir ?**

**Avec quelle intensité ?**

**Pendant combien de temps ?**

**Où se trouve la pluie autour de moi ?**

L'utilisateur doit pouvoir ouvrir Chetiwa, prendre une décision et fermer l'application en quelques secondes.

La faible durée d'utilisation est volontaire.

---

# 2. Règle produit

> **Une ouverture = une réponse.**

Chaque élément de l'application doit être évalué avec une question :

> Est-ce que cette information aide réellement l'utilisateur à savoir quand sortir ?

Si non, elle ne fait pas partie du MVP.

---

# 3. Inspiration concurrentielle

Drops constitue une référence fonctionnelle intéressante pour deux concepts :

- Graph ;
- Radar.

Chetiwa peut utiliser ces concepts génériques.

Chetiwa ne doit cependant pas reproduire :

- leur identité visuelle ;
- leur structure exacte d'écran ;
- leurs composants ;
- leurs couleurs ;
- leurs illustrations ;
- leur mascotte ;
- leur paywall ;
- leurs textes ;
- leurs screenshots ;
- leur branding.

Chetiwa doit être immédiatement identifiable comme un produit différent.

---

# 4. Navigation MVP

Le MVP comporte seulement deux modes principaux :

## Graph

## Radar

Pas d'onglet Weather.

Pas d'onglet 14 jours.

Pas de navigation complexe.

Le mode utilisé précédemment peut être restauré à la prochaine ouverture.

Lors du premier lancement :

**Graph** est sélectionné.

---

# 5. Structure de l'écran principal

```text
┌─────────────────────────────┐
│ Chetiwa        Paris    ⚙   │
│                             │
│ Pluie dans ~18 min          │
│ Modérée · environ 27 min    │
│                             │
│ Sec ensuite jusqu'à 20:10   │
│                             │
│    GRAPH       RADAR        │
│                             │
│      2 H       24 H         │
│                             │
│                             │
│        contenu              │
│                             │
└─────────────────────────────┘
```

Le résumé météo reste stable lorsqu'on passe de Graph à Radar.

Cela crée la continuité entre les deux représentations.

## 5.1 Sélection mondiale d'un lieu

Le sélecteur de lieu propose :

- un champ de recherche mondiale par ville ou code postal ;
- des résultats localisés dans la langue de l'application avec région et pays ;
- une action « Utiliser ma position actuelle » ;
- les lieux récemment sélectionnés ;
- une courte liste de villes populaires lorsque la recherche est vide.

La localisation est demandée uniquement après une action explicite de
l'utilisateur et uniquement pendant l'utilisation de l'application. Un refus,
une désactivation du service ou une recherche réseau impossible affiche un état
compréhensible et réessayable sans bloquer la liste manuelle. Lorsque le service
GPS est coupé ou l'autorisation bloquée, cet état propose une action directe vers
les réglages système appropriés. La résolution de position tente une mesure
actuelle puis utilise la dernière position connue comme repli si le capteur ne
répond pas dans le délai imparti. La sélection met à jour Graph, Radar et
Prévisions avec les mêmes coordonnées.

---

# 6. Chetiwa Weather Brief

Le composant le plus important n'est ni le radar ni le graphique.

C'est :

## Weather Brief

Exemples :

### Temps sec

**Pas de pluie prévue**

Sec pendant au moins 2 h.

---

### Pluie imminente

**Pluie dans ~12 min**

Modérée · environ 25 min.

---

### Pluie actuelle

**Il pleut maintenant**

Forte · accalmie estimée vers 18:48.

---

### Plusieurs épisodes

**Première averse vers 18:20**

18:20–18:46 · modérée

Nouvelle averse possible vers 20:15.

---

# 7. Rain Windows

Chetiwa transforme les données météo en périodes compréhensibles.

Exemple :

**17:34 → 18:17**
Fenêtre sèche

**18:17 → 18:48**
Pluie modérée

**18:48 → 20:12**
Fenêtre sèche

**20:12 → 20:31**
Pluie faible

Cette notion devient une signature fonctionnelle Chetiwa.

---

# 8. Graph — 2 heures

La vue par défaut.

Objectif :

voir précisément la pluie à très court terme.

Le graphique représente :

- Maintenant ;
- début de pluie ;
- évolution de l'intensité ;
- maximum ;
- fin de pluie.

Les données seront normalisées vers :

```dart
enum RainIntensity {
  none,
  light,
  moderate,
  heavy,
}
```

---

# 9. Design du graphique

Utiliser un Area Chart contemporain.

Pas de gros quadrillage.

Pas de tableau météo.

Pas d'informations parasites.

Principaux repères :

**Faible**

**Modérée**

**Forte**

Axe horizontal :

temps.

Une ligne distincte :

**Maintenant**

L'origine temporelle du Graph est toujours l'heure murale réelle du lieu
sélectionné, calculée au moment de l'affichage et mise à jour pendant que
l'écran reste ouvert. Elle ne doit jamais être remplacée par l'heure arrondie
du dernier pas du modèle (par exemple 19:45 lorsque le téléphone affiche
19:58). Si les données sont fournies par pas de 15 minutes, Chetiwa interpole la
valeur à l'instant présent afin que la courbe commence exactement à
« Maintenant ». L'horodatage de mise à jour du fournisseur reste une métadonnée
distincte.

---

# 10. Interaction Graph

L'utilisateur peut glisser horizontalement.

Un curseur apparaît.

Exemple :

**18:26**

**1,8 mm/h**

**Pluie modérée**

Ajouter un feedback haptique très discret lors du franchissement d'un changement important d'intensité.

---

# 11. Graph — 24 heures

Le même écran passe de :

**2 H**

à :

**24 H**

Pas besoin d'un écran Weather séparé.

Le 24 H sert à planifier la journée.

Il affiche principalement :

- pluie ;
- température ;
- périodes sèches ;
- épisodes de pluie.

Le vent et les autres métriques restent secondaires.

---

# 12. Radar

Le Radar doit être immersif.

Le maximum d'espace doit être consacré à la carte.

## Hiérarchie obligatoire de l'écran

Sur mobile, la carte doit occuper tout l'espace restant entre le sélecteur de
ville et la timeline. Les informations déjà présentes dans le header, le Rain
Brief ou le Graph ne doivent pas être répétées sous forme de grandes cartes.

Le Radar conserve uniquement :

- une ligne de contexte météo compacte et translucide ;
- le bouton de couches ;
- un bouton de recentrage ;
- une légende de précipitations compacte ;
- la timeline et le bouton lecture.

La timeline inclut une mini-courbe de précipitation au point sélectionné. Cette
courbe utilise les pas de 15 minutes disponibles sur la même fenêtre temporelle
que les observations radar. Elle ne doit jamais être présentée comme une mesure
de réflectivité de toute la carte.

La mini-courbe Radar est explicitement nommée « Pluie passée au point » : elle
explique les deux heures d'observations historiques et s'arrête à la dernière
image radar. Le Graph principal est explicitement nommé « Prévision de pluie »
et commence à l'heure actuelle pour couvrir les deux ou vingt-quatre prochaines
heures. Ces deux courbes ne doivent jamais employer le même libellé générique,
car l'une décrit le passé et l'autre le futur.

Lorsque l'utilisateur sélectionne une image historique, la ligne de contexte
Radar affiche la pluie estimée au point et l'heure historique sélectionnée. Elle
ne continue pas d'afficher silencieusement les métriques actuelles.

Les contrôles secondaires de couches, d'opacité et de fond de carte sont
regroupés dans une bottom sheet. Ils ne restent pas ouverts au-dessus de la
carte.

Afficher :

- position utilisateur ;
- précipitations ;
- principales villes/routes ;
- timeline ;
- bouton lecture.

Éviter les POI inutiles.

Le pin de ville doit rester petit et ne jamais masquer les échos radar. Le nom
de la ville est déjà disponible dans le sélecteur global et ne doit pas être
répété en permanence sur la carte.

Le débit de pluie affiché dans la ligne de contexte est une mesure **au point
sélectionné**. Les couleurs de la carte sont des échos radar **régionaux** :
leur présence ailleurs dans la zone visible ne contredit donc pas « 0 mm/h ici ».
L'interface emploie explicitement ces libellés et ne présente jamais le bleu de
la légende comme une pluie au point utilisateur.

Le radar ne doit jamais appeler un écho « nuage » : la réflectivité radar ne
mesure pas la couverture nuageuse. L'affichage Chetiwa restitue chaque cellule
avec une hiérarchie concentrique stable : halo gris clair diffus, empreinte
intérieure gris foncé, puis noyau orange, rouge et rouge sombre lorsque la
réflectivité augmente. Les gris signifient explicitement « écho faible ou
incertain » et jamais « pluie confirmée » ; ils restent suffisamment transparents
pour ne pas former un tapis opaque sur la carte. Les faibles réflectivités peuvent
correspondre à du bruit radar, à une propagation anormale, à de la virga ou à des
précipitations trop faibles pour atteindre le sol. Un interrupteur « Échos
faibles » augmente leur visibilité pour les utilisateurs avancés et reste
désactivé par défaut. La palette source du fournisseur reste également accessible
dans les couches.

Le fond par défaut est une imagerie satellite/terrain lisible avec frontières
et noms de villes. Les fonds sombre, clair et routes restent disponibles. Tout
fond tiers doit afficher son attribution dans la carte et utiliser une clé ou
une licence de production conforme aux conditions du fournisseur.

Interactions minimales :

- pinch pour zoomer ;
- double-tap sur la carte pour zoomer ;
- double-tap sur le pin pour centrer la ville à un niveau de détail local ;
- déplacement libre de la carte ;
- bouton dédié pour revenir à la ville avec un cadrage régional.

Le zoom reste volontairement borné entre une vue régionale et une vue ville.
Chetiwa ne permet ni un recul mondial inutile ni un zoom de quartier qui
agrandirait artificiellement les pixels radar au-delà de leur résolution native.

---

# 13. Radar Timeline

Exemple avec un fournisseur d'observations historiques :

```text
-120m        -60m       DERNIÈRE IMAGE    MAINTENANT
 ─────────────────────────●··············│
                          ▶
```

L'utilisateur peut :

- scruber ;
- lire l'animation ;
- revenir à la dernière image radar disponible.

La timeline ne doit pas utiliser l'apparence d'un slider générique. Elle prend
la forme d'une règle horaire directement manipulable :

- un curseur vertical rouge indique l'image sélectionnée ;
- des repères et heures restent lisibles sous la règle ;
- un drag ou tap sélectionne l'image radar la plus proche ;
- le curseur rouge avance pendant la lecture ;
- la position horizontale des trames, des heures, de la courbe et du curseur est
  calculée depuis leurs timestamps réels, jamais depuis leur simple index ;
- les heures sont affichées dans le fuseau du lieu sélectionné ;
- la sélection manuelle doit rester possible pendant ou après l'animation ;
- la date/heure sélectionnée et le statut « Historique », « Dernière image »,
  « Maintenant » ou « Prévision » sont affichés de manière compacte ;
- une image ancienne ne doit jamais être présentée comme l'état actuel ;
- le bouton lecture repart de la plus ancienne observation disponible, avance
  jusqu'à la dernière image disponible, puis recommence automatiquement en
  boucle ;
- un bouton de relance remet immédiatement le curseur sur la plus ancienne
  observation et redémarre la boucle, même si elle était en pause ;
- lorsqu'une image historique est sélectionnée, un contrôle visible permet de
  revenir immédiatement à la dernière image.

Le domaine de la timeline se termine à l'heure murale réelle. Lorsque le
fournisseur a du retard, un repère « MAINT. » reste à droite et le curseur de la
dernière observation apparaît à son véritable timestamp, accompagné de son âge
(par exemple « Dernière image · il y a 9 min »). Le vide entre les deux est
intentionnel : Chetiwa ne fabrique pas de radar futur.

Avec RainViewer public, la timeline contient les deux dernières heures
d'observations, généralement espacées de 10 minutes. Le nowcast futur n'étant
plus disponible depuis janvier 2026, aucune trame future ne doit être simulée
ou présentée comme une observation. Si un fournisseur commercial de nowcast est
ajouté plus tard, ses trames futures devront être identifiées explicitement
comme « Prévision ».

Les données futures doivent être clairement distinguées des observations radar.

---

# 14. Signature UX Chetiwa

Chetiwa doit posséder sa propre identité.

Deux éléments fondamentaux :

## Rain Brief

et

## Rain Windows

Le Radar et le Graph sont des représentations.

Rain Brief et Rain Windows constituent la valeur décisionnelle de Chetiwa.

---

# 15. Direction UI

Style :

- moderne ;
- minimal ;
- premium mais accessible ;
- fluide ;
- calme ;
- météo sans aspect enfantin.

Éviter les interfaces remplies de cartes.

Éviter les énormes headers.

Éviter une couleur différente pour chaque information.

---

# 16. Flutter Design Foundation

Utiliser Material 3 comme fondation technique.

Construire ensuite un Design System spécifique Chetiwa.

Ne pas laisser les valeurs visuelles dispersées directement dans les widgets.

Centraliser :

```dart
ChetiwaColors
ChetiwaTypography
ChetiwaSpacing
ChetiwaRadius
ChetiwaElevation
ChetiwaMotion
```

Puis exposer autant que possible ces valeurs via le thème Flutter.

---

# 17. Figma Design System

Pages recommandées :

```text
00 Product
01 Foundations
02 Components
03 Graph
04 Radar
05 Onboarding
06 Settings
07 Monetization
08 States
09 Prototype
10 Dev Handoff
```

---

# 18. Figma Foundations

Créer des Variables.

### Colors

```text
background.primary
background.secondary

surface.primary
surface.secondary

text.primary
text.secondary

rain.none
rain.light
rain.moderate
rain.heavy

accent.primary
warning
error
```

### Spacing

```text
4
8
12
16
20
24
32
40
48
```

### Radius

```text
small
medium
large
full
```

---

# 19. Light / Dark

Chetiwa doit supporter dès le MVP :

**System**

**Light**

**Dark**

Le radar peut particulièrement bénéficier du thème sombre.

Les designs Light et Dark sont définis dans Figma avec les mêmes tokens sémantiques.

---

# 20. Flutter Architecture

Architecture :

```text
Presentation
     │
Application / BLoC
     │
Domain
     │
Repositories
     │
Data Sources
```

Avec organisation **feature-first**.

---

# 21. Structure projet

```text
lib/
│
├── app/
│   ├── app.dart
│   ├── router/
│   ├── theme/
│   └── di/
│
├── core/
│   ├── errors/
│   ├── network/
│   ├── location/
│   ├── analytics/
│   └── utils/
│
├── features/
│   │
│   ├── forecast/
│   │   ├── presentation/
│   │   ├── application/
│   │   ├── domain/
│   │   └── data/
│   │
│   ├── radar/
│   │   ├── presentation/
│   │   ├── application/
│   │   ├── domain/
│   │   └── data/
│   │
│   ├── location/
│   ├── alerts/
│   ├── subscription/
│   └── settings/
│
└── main.dart
```

---

# 22. BLoC Strategy

Ne pas créer un Bloc pour chaque petit élément UI.

Utiliser **Cubit** pour un état simple.

Exemple :

```text
ThemeCubit
SettingsCubit
LocationCubit
GraphHorizonCubit
```

Utiliser **Bloc** lorsque plusieurs événements métier conduisent à plusieurs transitions d'état.

Exemple :

```text
ForecastBloc
RadarBloc
SubscriptionBloc
ConsentBloc
RainAlertBloc
```

---

# 23. Exemple ForecastBloc

Events :

```dart
sealed class ForecastEvent {}

final class ForecastRequested extends ForecastEvent {}

final class ForecastRefreshed extends ForecastEvent {}

final class ForecastLocationChanged extends ForecastEvent {
  final Coordinates coordinates;
}
```

States :

```dart
sealed class ForecastState {}

final class ForecastInitial extends ForecastState {}

final class ForecastLoading extends ForecastState {}

final class ForecastReady extends ForecastState {
  final WeatherBrief brief;
  final List<RainPoint> points;
  final List<RainWindow> windows;
}

final class ForecastFailure extends ForecastState {}
```

---

# 24. Domain indépendant des APIs

L'UI ne doit jamais connaître directement :

```text
Open-Meteo
Météo-France
Rainbow
```

Elle manipule uniquement le modèle Chetiwa.

---

# 25. Domain Model

```dart
class RainPoint {
  final DateTime time;
  final double rateMmPerHour;
  final double? probability;
  final RainIntensity intensity;
}

class RainWindow {
  final DateTime start;
  final DateTime? end;
  final RainIntensity intensity;
}

class WeatherBrief {
  final WeatherBriefType type;
  final DateTime? rainStart;
  final DateTime? rainEnd;
  final RainIntensity intensity;
}
```

---

# 26. Repository Pattern

```dart
abstract interface class ForecastRepository {
  Future<Forecast> getForecast(Coordinates coordinates);
}

abstract interface class RadarRepository {
  Future<List<RadarFrame>> getFrames(
    Coordinates coordinates,
  );
}
```

Implémentations :

```text
ForecastRepositoryImpl
RadarRepositoryImpl
```

---

# 27. Provider abstraction

```text
ForecastProvider
 ├── OpenMeteoProvider
 └── MeteoFranceProvider

RadarProvider
 ├── CommercialRadarProvider
 └── MeteoFranceRadarProvider
```

Changer de fournisseur ne doit pas nécessiter de modifier l'UI.

---

# 28. Navigation Flutter

Utiliser un router déclaratif.

Routes approximatives :

```text
/
 /onboarding
 /weather
 /settings
 /subscription
 /privacy
```

Le changement Graph/Radar n'est pas nécessairement une nouvelle page.

Il peut être un état interne de l'écran principal.

---

# 29. Graph Flutter

Encapsuler entièrement la bibliothèque graphique.

```dart
class ChetiwaRainChart extends StatelessWidget {
  final List<RainPoint> points;
  final DateTime now;
}
```

Aucun autre composant ne doit dépendre directement de la librairie de chart.

Cela permet de la remplacer ultérieurement.

---

# 30. Performance

Utiliser :

- widgets `const` lorsque possible ;
- petites zones de rebuild ;
- `BlocSelector` lorsque pertinent ;
- cache des données ;
- décodage ou transformation lourde hors du rendu ;
- listes paresseuses ;
- limitation des animations inutiles.

Le Radar ne doit pas reconstruire toute la page à chaque frame.

---

# 31. Cache Strategy

À l'ouverture :

1. lire les dernières données locales ;
2. afficher immédiatement ;
3. déclencher le refresh ;
4. remplacer silencieusement les données.

Pattern :

**stale while revalidate**

Objectif :

aucun écran blanc lors du lancement normal.

---

# 32. Backend MVP

Ne pas construire une architecture distribuée.

Un seul backend Chetiwa.

```text
Flutter
   │
   ▼
Chetiwa API
   │
   ├── Forecast Provider
   ├── Radar Provider
   ├── Alerts
   └── Subscription Validation
```

Pas de Kubernetes.

Pas de Kafka.

Pas de microservices.

---

# 33. Business Model

Chetiwa doit pouvoir être utilisée gratuitement.

Deux offres :

## Chetiwa Free

## Chetiwa+

---

# 34. Chetiwa Free

Inclut :

- Weather Brief ;
- Graph 2 h ;
- Graph 24 h ;
- Radar ;
- position actuelle ;
- Rain Windows ;
- paramètres essentiels.

Le produit gratuit doit être suffisamment bon pour générer de la rétention.

---

# 35. Publicité

Chetiwa Free peut contenir de la publicité.

Principe absolu :

> **La publicité ne doit jamais empêcher l'utilisateur d'obtenir immédiatement sa réponse météo.**

Ne jamais afficher une publicité plein écran au lancement.

Ne jamais bloquer Graph ou Radar derrière une publicité.

Ne jamais déclencher une publicité pendant le scrub du graphique.

## Règle de mise en page publicitaire

L'espace publicitaire est réservé dès le calcul initial du layout afin
d'éviter tout saut de contenu lors du chargement de la création.

Sur l'écran météo principal :

- le slot est placé entre le contenu Graph/Radar/Prévisions et la navigation ;
- il ne recouvre jamais la carte, la timeline, le Graph ou la navigation ;
- hauteur cible mobile : 50 à 60 dp, largeur adaptative disponible ;
- le slot disparaît entièrement pour Chetiwa+ ;
- en absence de création, le produit peut réduire visuellement le slot, mais
  ne doit jamais déplacer un contrôle pendant une interaction ;
- aucune publicité ne peut apparaître ou se rafraîchir pendant un scrub radar
  ou graphique.

---

# 36. Formats publicitaires

Priorité :

### Adaptive Banner

ou

### Native Ad

Les emplacements doivent être testés.

Exemple acceptable :

```text
Weather Brief

Graph

────────────
Sponsored
[ native ad ]
────────────
```

ou un petit adaptive banner dans le slot réservé au-dessus de la navigation.
Le banner n'est jamais superposé à la carte et n'est jamais fixé par-dessus la
timeline Radar.

---

# 37. Chetiwa+

Chetiwa+ n'est pas seulement « supprimer les pubs ».

Chetiwa+ apporte :

### Aucun 광고 / aucune publicité

### Smart Rain Alerts

### Plusieurs lieux enregistrés

### Widgets

### Alertes personnalisées

### Radar étendu

### Historique / prévision radar supplémentaires si les données le permettent

---

# 38. Smart Rain Alerts

C'est probablement la fonctionnalité Premium la plus importante.

Exemple :

**🌧️ Chetiwa**

Une averse modérée devrait commencer dans environ 12 min à Paris.

---

Configuration Premium possible :

```text
Préviens-moi :

[✓] 5 min avant
[✓] 10 min avant
[ ] 20 min avant

Intensité minimum :

Faible
Modérée
Forte
```

---

# 39. Multiple Locations

Free :

**1 localisation principale**

Chetiwa+ :

```text
Ma position
Maison
Travail
École
Parents
```

Une alerte peut être activée individuellement pour chaque lieu.

---

# 40. Pricing initial à tester

Hypothèse de départ :

### 1,49 € / mois

ou

### 9,99 € / an

Le plan annuel doit être le plan recommandé.

Les prix devront être A/B testés après obtention d'un volume suffisant.

---

# 41. Pas de Lifetime comme modèle principal

Chetiwa possède des dépenses récurrentes :

- données ;
- backend ;
- push ;
- monitoring ;
- maintenance.

Un achat permanent ne correspond donc pas idéalement au coût du service.

Une offre Founders ponctuelle peut éventuellement être expérimentée pendant le lancement, mais ce n'est pas le business model principal.

---

# 42. Purchases Flutter

La couche application ne connaît pas directement StoreKit ou Google Billing.

```text
SubscriptionRepository
      │
      ├── App Store
      └── Google Play
```

Domain :

```dart
enum SubscriptionStatus {
  free,
  premium,
  gracePeriod,
  expired,
}
```

---

# 43. Ads Architecture

Créer :

```text
AdsRepository
ConsentRepository
```

L'UI demande simplement :

```dart
state.canShowAds
```

Elle ne décide pas elle-même des règles RGPD ou premium.

---

# 44. Consent

Avant de charger une publicité personnalisée lorsque nécessaire :

```text
ConsentBloc
      │
      ▼
ConsentRepository
      │
      ▼
CMP / UMP
```

Le choix de consentement doit rester accessible depuis Settings.

---

# 45. Paywall

Pas de copie du paywall Drops.

Chetiwa utilise un écran beaucoup plus léger.

Exemple :

```text
             Chetiwa+

Sors sans surprise.

✓ Alertes avant la pluie
✓ Plusieurs lieux
✓ Widgets
✓ Radar avancé
✓ Aucune publicité


     9,99 € / an
     1,49 € / mois

   [ Essayer Chetiwa+ ]

Restaurer mes achats
```

---

# 46. Pas de paywall agressif

Ne pas afficher le paywall au premier lancement.

Premièrement :

laisser l'utilisateur découvrir le produit.

Un moment intéressant pour présenter Chetiwa+ :

lorsqu'il demande :

**« Me prévenir avant cette pluie »**

Puis :

> Les Smart Alerts font partie de Chetiwa+.

Le premium apparaît alors au moment où sa valeur est compréhensible.

---

# 47. Onboarding

Maximum trois étapes.

## 1

**La pluie, avant qu'elle arrive.**

Sache quand sortir en quelques secondes.

---

## 2

**Où êtes-vous ?**

Autorisez votre position pour voir les prochaines averses autour de vous.

---

## 3

Accès direct à Graph.

Ne pas demander :

- notifications ;
- tracking publicitaire ;
- création de compte ;

avant qu'ils ne soient nécessaires.

---

# 48. Notifications

Demander l'autorisation seulement lorsque l'utilisateur active les alertes.

Avant le popup système, expliquer :

**Être prévenu avant la pluie ?**

Chetiwa peut vous alerter quelques minutes avant une averse.

CTA :

**Activer les alertes**

---

# 49. Account

Pas de compte obligatoire dans le MVP.

Chetiwa Free fonctionne immédiatement.

Un compte pourra éventuellement être ajouté plus tard pour synchroniser :

- lieux ;
- préférences ;
- premium ;
- appareils.

---

# 50. Tracking Analytics

Événements produit :

```text
app_opened

forecast_loaded

graph_viewed
radar_viewed

graph_2h_selected
graph_24h_selected

graph_scrubbed

radar_played

alert_cta_clicked
alert_enabled

paywall_viewed
subscription_started
subscription_purchased

ad_impression
```

Ne pas collecter des données qui n'apportent aucune valeur produit.

---

# 51. KPI business

Suivre :

## Acquisition

Installations.

## Activation

Utilisateur ayant obtenu avec succès une première prévision.

## Retention

D1  
D7  
D30

## Usage

Open / active user / week.

## Ads

Revenue / active free user.

## Premium

Paywall conversion.

Trial conversion si trial.

Monthly churn.

Annual subscription renewal.

---

# 52. North Star Metric

Une métrique particulièrement intéressante :

## Weekly Weather Decisions

Nombre de sessions où l'utilisateur obtient une Weather Brief exploitable.

L'objectif n'est pas de maximiser artificiellement le temps passé.

L'objectif est de devenir un réflexe.

---

# 53. Expansion business future

Ne pas construire ces éléments dans le MVP, mais garder l'architecture compatible.

Possibilités futures :

### B2B

Services météo pluie pour :

- coursiers ;
- livraison ;
- événements ;
- restaurants avec terrasse ;
- sports ;
- entreprises terrain.

### Widgets/API

API simplifiée :

> « Pluie dans les prochaines 60 minutes ? »

pour applications tierces.

Cela peut devenir une deuxième activité différente de la monétisation grand public.

---

# 54. Roadmap

## Phase 1 — Product / Figma

Créer :

- Design System ;
- Weather Brief ;
- Graph ;
- Radar ;
- onboarding ;
- settings ;
- paywall ;
- Light/Dark ;
- états loading/error/offline.

---

## Phase 2 — Flutter Shell

- architecture ;
- router ;
- thème ;
- BLoC ;
- dependency injection ;
- i18n.

---

## Phase 3 — Fake Weather

Créer plusieurs fixtures :

```text
dry.json
light_rain.json
heavy_rain.json
multiple_showers.json
storm.json
```

Construire toute l'expérience sans dépendre des APIs.

---

## Phase 4 — Forecast

Brancher le fournisseur météo.

Construire :

```text
RainPoint
RainWindow
WeatherBrief
```

---

## Phase 5 — Graph

Implémenter :

- 2 h ;
- 24 h ;
- cursor ;
- gestures ;
- animations.

---

## Phase 6 — Radar

- map ;
- radar overlay ;
- timeline ;
- animation ;
- position utilisateur.

---

## Phase 7 — Ads

- consent ;
- Google Mobile Ads ;
- placements ;
- analytics.

---

## Phase 8 — Chetiwa+

- StoreKit ;
- Google Play Billing ;
- restore purchases ;
- premium entitlement.

---

## Phase 9 — Smart Alerts

- device token ;
- saved location ;
- alert engine ;
- anti-spam ;
- push.

---

## Phase 10 — Beta

- TestFlight ;
- Google Play testing ;
- crash monitoring ;
- analytics ;
- tests de précision météo.

---

# 55. MVP Final

Au lancement, Chetiwa doit faire extrêmement bien :

### 1. Weather Brief

### 2. Graph 2 h

### 3. Graph 24 h

### 4. Radar

### 5. Rain Windows

### 6. Publicité discrète pour Free

### 7. Chetiwa+ sans publicité

### 8. Smart Alerts Premium

Tout le reste est secondaire.

---

# 56. Différenciation finale

Drops :

**voir les données de pluie.**

Chetiwa :

**savoir quand sortir.**

Le Radar et le Graph sont les instruments.

La véritable expérience Chetiwa est :

**Weather Brief + Rain Windows + Smart Alerts.**

---

# 57. Vision de marque

## Chetiwa

### La pluie, avant qu'elle arrive.

Ou :

### Sors au bon moment.

Store France :

**Chetiwa — Pluie & Radar**

Sous-titre :

**Pluie dans l'heure et radar météo**

---

# 58. Principe final

Chetiwa ne gagnera pas en ajoutant plus de météo.

Elle peut gagner en affichant **moins de choses, mais les bonnes choses au bon moment**.

L'expérience idéale :

```text
Ouvrir Chetiwa

        ↓

"Pluie dans ~16 min"

        ↓

Voir le Graph

        ↓

Éventuellement regarder Radar

        ↓

Décider

        ↓

Fermer
```

Temps nécessaire :

**quelques secondes.**

C'est le produit.
