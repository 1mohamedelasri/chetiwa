# Vigilance officielle Météo-France

## Contrat produit

- Source unique : `cartevigilance/encours` de l’API Bulletin Vigilance Météo-France.
- Ciblage : département INSEE résolu depuis le lieu principal avec `geo.api.gouv.fr`.
- Seuil initial : orange et rouge. Le jaune reste un choix explicite.
- Catégories : vent, pluie-inondation, orages, crues, neige-verglas, canicule,
  grand froid et avalanches.
- Vagues-submersion reste désactivé tant que Chetiwa ne cible pas précisément
  les sous-domaines littoraux (`dd10`).
- Une prévision de forte pluie n’est jamais convertie en vigilance ou en orage.

Le moteur envoie une activation, un changement de niveau et une fin. L’outbox
Firestore déduplique les événements et FCM remplace l’ancienne notification du
même phénomène/département.

## Configuration

```ini
VIGILANCE_ALERTS_ENABLED=true
VIGILANCE_ALERTS_SEND_ENABLED=false
METEO_FRANCE_APPLICATION_ID=<secret>
```

`METEO_FRANCE_APPLICATION_ID` est la valeur attendue après `Authorization:
Basic`. Une clé Bearer permanente peut être fournie à la place via
`METEO_FRANCE_VIGILANCE_API_KEY`. Les secrets ne doivent pas entrer dans Git.

## Déploiement sûr

1. Créer le secret Météo-France dans Secret Manager.
2. Déployer l’API avec Firestore et `VIGILANCE_ALERTS_ENABLED=true`.
3. Provisionner le job :

```bash
backend/deploy/alerts/provision-vigilance-worker.sh \
  PROJECT_ID REGION IMAGE WORKER_SA SCHEDULER_SA ENV_FILE SECRET_NAME
```

4. Garder `VIGILANCE_ALERTS_SEND_ENABLED=false` pour vérifier les propositions
   en shadow mode.
5. Tester Android et iOS avec un appareil réel, puis activer l’envoi.

Le job interroge une seule fois le produit national toutes les cinq minutes. Un
produit futur ou vieux de plus de 26 heures est rejeté et aucun push n’est créé.
