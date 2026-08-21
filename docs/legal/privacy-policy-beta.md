# Politique de confidentialité — Chetiwa (bêta privée)

**Statut : brouillon à publier avant toute distribution externe.**

À compléter avant publication : `[ENTITÉ LÉGALE]`, `[ADRESSE]`, `[E-MAIL
SUPPORT]`, `[URL PUBLIQUE]` et date d’effet. Ce document décrit uniquement le
MVP actuel : il ne doit pas être conservé tel quel si publicité, achats,
analytics, compte, push distant ou backend sont activés.

## Ce que fait Chetiwa

Chetiwa affiche des prévisions, un radar et des graphiques de pluie. Vous pouvez
choisir un lieu en le recherchant, sur la carte ou en utilisant votre position
actuelle. La position n'est demandée qu'après votre action et Chetiwa ne suit pas
votre position en arrière-plan.

## Données et stockage dans le MVP

| Donnée | Utilisation | Stockage/partage |
| --- | --- | --- |
| Lieu principal et villes récentes | Afficher votre météo | Sur votre appareil ; supprimables depuis l'app |
| Position actuelle | Afficher la météo du point choisi | Utilisée ponctuellement ; non enregistrée comme position GPS |
| Coordonnées du lieu consulté | Demander météo/radar/carte | Envoyées aux fournisseurs affichant ces données ; voir attributions |
| Préférences d'alertes | Configurer l'interface locale | Sur votre appareil |
| Autorisation de notifications | Afficher les alertes locales lorsqu'elles seront activées | Gérée par le système ; aucun token push distant dans le MVP |

Le MVP n'utilise ni compte utilisateur, ni publicité, ni abonnement, ni profil
publicitaire. Le SDK Firebase Analytics est configuré, mais sa collecte est
désactivée par défaut. L'utilisateur peut l'activer depuis Réglages après une
explication claire, puis retirer ce choix au même endroit. Il ne transmet pas de
coordonnées à un serveur Chetiwa dans sa configuration bêta locale.

## Fournisseurs de données

Les requêtes météo, géocodage, radar et carte peuvent être adressées aux
fournisseurs identifiés dans le registre :
[`../compliance/provider-register.md`](../compliance/provider-register.md).
Leur politique et leurs conditions applicables doivent être vérifiées et les
attributions visibles avant toute bêta externe ou monétisée.

## Vos choix

- Vous pouvez utiliser la recherche ou la carte sans autoriser le GPS.
- Vous pouvez refuser ou retirer l'autorisation de localisation/notification
  depuis les réglages du système.
- Vous pouvez effacer le lieu principal dans Réglages et supprimer chaque lieu
  récent dans le sélecteur de lieu.

## Contact et modifications

Pour toute demande relative aux données, contactez `[E-MAIL SUPPORT]`. Toute
modification substantielle de cette politique sera publiée à `[URL PUBLIQUE]`
avant de prendre effet.
