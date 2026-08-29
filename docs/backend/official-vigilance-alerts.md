# Alertes officielles France et Europe

## Contrat produit

- Sources : MeteoAlarm/EUMETNET via MeteoGate pour l’Europe, avec Météo-France
  en complément lorsqu’un accès au portail est disponible.
- Ciblage : polygones officiels exacts MeteoAlarm. En France, le département
  INSEE est également conservé pour le flux Météo-France.
- Seuil initial : orange et rouge. Le jaune reste un choix explicite.
- Catégories : vent, pluie-inondation, orages, crues, neige-verglas, canicule,
  grand froid, avalanches, submersion côtière, brouillard, feux de forêt et
  sécheresse.
- Une prévision de forte pluie n’est jamais convertie en vigilance ou en orage.

Le moteur envoie une activation, un changement de niveau et une fin. L’outbox
Firestore déduplique les événements et FCM remplace l’ancienne notification du
même phénomène et de la même zone.

## Configuration

```ini
VIGILANCE_ALERTS_ENABLED=true
VIGILANCE_ALERTS_SEND_ENABLED=false
METEOALARM_ALERTS_ENABLED=true
METEOALARM_API_KEY=<secret-manager>
```

`METEOALARM_API_KEY` est la clé `apikey` fournie par MeteoGate. Elle est requise
uniquement dans le worker. `METEO_FRANCE_APPLICATION_ID` ou
`METEO_FRANCE_VIGILANCE_API_KEY` reste optionnel : si Météo-France est absent ou
échoue, MeteoAlarm couvre aussi la France.

## Déploiement sûr

1. Créer le secret MeteoGate dans Secret Manager.
2. Déployer l’API avec Firestore et `VIGILANCE_ALERTS_ENABLED=true`.
3. Provisionner le job :

```bash
backend/deploy/alerts/provision-vigilance-worker.sh \
  PROJECT_ID REGION IMAGE WORKER_SA SCHEDULER_SA ENV_FILE "" METEOALARM_SECRET_NAME
```

4. Garder `VIGILANCE_ALERTS_SEND_ENABLED=false` pour vérifier les propositions
   en shadow mode.
5. Tester Android et iOS avec un appareil réel, puis activer l’envoi.

Le job interroge une seule fois le flux européen toutes les cinq minutes, puis
réutilise ce snapshot pour tous les utilisateurs. Il n’effectue pas un appel par
utilisateur. Les alertes annulées, expirées ou hors du polygone officiel sont
ignorées.
