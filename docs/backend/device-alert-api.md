# Device et règles d’alerte — API v1

Ce contrat prépare Smart Rain Alerts sans prétendre que l’envoi push est déjà
opérationnel. Le stockage mémoire est réservé au profil `local` et aux tests.
En `staging` et `production`, les routes répondent `503
persistent_store_not_configured` tant qu’un adaptateur persistant, sauvegardé et
testé n’est pas injecté.

## Identité et confidentialité

Toutes les routes exigent `X-Chetiwa-Device-Id`. Le backend valide cet
identifiant d’installation aléatoire puis ne conserve dans le store qu’un SHA-256.
Il ne l’associe ni à une adresse e-mail ni à un compte publicitaire. Le token push
et le hash interne ne sont jamais inclus dans les réponses.

La suppression de l’appareil supprime dans la même opération son token push et
toutes ses règles d’alerte. L’application ne doit enregistrer un token qu’après
une action explicite d’activation des alertes.

## Routes

### Enregistrer ou renouveler un appareil

`POST /v1/devices`

```json
{
  "platform": "ios",
  "locale": "fr",
  "timeZone": "Europe/Paris",
  "notificationsEnabled": true,
  "pushToken": "token-fourni-par-apns-ou-fcm"
}
```

`platform` accepte `ios` ou `android`. `locale` accepte `fr` ou `en`. Le token
est obligatoire lorsque `notificationsEnabled` vaut `true`. Réenregistrer le
même appareil renouvelle son token sans créer de doublon.

### Supprimer l’appareil courant

`DELETE /v1/devices` renvoie `204`. Cette opération supprime aussi toutes les
règles liées à l’installation.

### Gérer les règles

- `GET /v1/alerts`
- `POST /v1/alerts`
- `PATCH /v1/alerts/{alertId}`
- `DELETE /v1/alerts/{alertId}`

Corps de création :

```json
{
  "location": {
    "label": "Paris, France",
    "latitude": 48.8566,
    "longitude": 2.3522,
    "timeZone": "Europe/Paris"
  },
  "leadMinutes": 15,
  "minimumIntensity": "moderate",
  "quietHours": {
    "enabled": true,
    "start": "22:00",
    "end": "07:00"
  },
  "enabled": true
}
```

Contraintes MVP :

- cinq règles maximum par installation ;
- délai de 5 à 120 minutes ;
- intensité `light`, `moderate` ou `heavy` ;
- heures silencieuses au format local `HH:mm`, interprétées dans le fuseau du
  lieu ;
- un appareil ne peut ni lire ni modifier les règles d’une autre installation.

`PATCH` accepte tout sous-ensemble non vide des champs de création. Les réponses
utilisent l’enveloppe `{data, meta}` commune et `Cache-Control: no-store`.

## Ce qui reste avant production

1. Implémenter l’adaptateur Firestore avec index, TTL d’inactivité, migrations,
   sauvegarde et restauration testée.
2. Ajouter App Check/attestation et une limite distribuée.
3. Configurer APNs/FCM par environnement et renouveler les tokens invalides.
4. Construire le moteur nowcast avec déduplication, cooldown et quiet hours.
5. Tester silencieusement les faux positifs/faux négatifs avant toute alerte
   utilisateur.

