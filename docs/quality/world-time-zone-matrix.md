# Matrice mondiale des heures locales

Cette matrice vérifie que Chetiwa conserve les instants en UTC et affiche les
heures avec le fuseau IANA du lieu sélectionné, jamais avec le fuseau du
téléphone.

## Villes de référence

| Ville | Fuseau IANA | Cas couvert |
| --- | --- | --- |
| Honolulu | `Pacific/Honolulu` | date locale précédente, UTC−10 |
| New York | `America/New_York` | date locale précédente, heure d’été |
| Paris | `Europe/Paris` | passage à minuit, heure d’été européenne |
| Dubaï | `Asia/Dubai` | passage à minuit sans heure d’été |
| Katmandou | `Asia/Kathmandu` | décalage non entier UTC+05:45 |
| Tokyo | `Asia/Tokyo` | date locale suivante |
| Sydney | `Australia/Sydney` | date suivante, heure d’été australe |
| Auckland | `Pacific/Auckland` | date suivante, UTC+12 |

## Contrat vérifié

Pour chaque ville, les tests contrôlent :

- la conversion de l’instant UTC vers la date et l’heure locales ;
- la conversion inverse sans perte ;
- l’offset calculé par la base IANA ;
- la date du premier jour de prévision ;
- le lever du soleil sur la bonne date locale ;
- la première heure de prévision ;
- la même heure dans les métriques, Graph, Radar et Prévisions.

Les passages d’heure d’été sont en plus vérifiés à New York et Sydney afin de
couvrir les deux hémisphères.

## Règle d’implémentation

Tous les écrans passent désormais par `WeatherTimeZone.hourMinute` ou
`WeatherTimeZone.hour`. Le formatage direct avec l’heure du téléphone est
interdit dans les surfaces météo.
