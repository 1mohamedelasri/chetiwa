# Gate conformité — lancement public

Statut : **BLOQUÉ tant que les preuves externes ne sont pas archivées**.

Ce document transforme la validation fournisseur en condition de release. Les
crédits affichés dans l’application ne constituent pas une autorisation
commerciale. Les contrats, licences et conditions acceptées doivent être
conservés dans un espace contrôlé par l’équipe, avec une copie datée et un
responsable identifié.

## Décisions techniques actuelles

| Composant | Utilisation actuelle | Décision de lancement | Preuve exigée |
| --- | --- | --- | --- |
| Prévisions/géocodage | Open-Meteo direct en dev, proxy en prod | Contrat/API commerciale avant pubs ou abonnements | Conditions acceptées, quota, attribution, DPA |
| Radar | LibreWXR auto-hébergé derrière Cloudflare | Bêta après gate technique ; public après validation du code et de chaque donnée amont | Licences, droit de redistribution, cache/CDN, attribution, capacité et procédure incident |
| Fond standard | CARTO dans le radar actuel | Remplacer par un fond explicitement autorisé ou signer l’offre adaptée | Licence mobile/commerciale, cache, attribution, quota |
| Satellite | Esri, actuellement fond Radar par défaut | Désactiver comme défaut ou configurer compte/token/budget avant publication | Token, droits d’application, cache, attribution, budget |
| Achats | Apple App Store / Google Play | Autoriser après validation des droits et textes store | Accords développeur, produits, commissions, fiscalité |
| Publicité | Slot Free, aucune requête Premium | Activer uniquement avec CMP et contrat publicitaire validés | DPA, consentement, ATT/App Privacy/Data Safety, attribution |

## Checklist de release

- [ ] Une personne responsable a signé la validation pour chaque fournisseur.
- [ ] LibreWXR et chacune de ses données amont actives sont autorisés pour les
  territoires, le cache et la redistribution de la build publiée.
- [ ] Le droit d’usage commercial, les territoires et la durée sont écrits.
- [ ] Le cache est expressément autorisé : durée, proxy/CDN, stockage disque,
  revalidation et préchargement.
- [ ] L’usage des tuiles dans une application payante et financée par publicité
  est couvert par les conditions ou le contrat.
- [ ] Les crédits exacts de la version publiée ont été vérifiés sur appareil.
- [ ] Les URLs de crédits et les conditions acceptées sont archivées.
- [ ] Les quotas, prix, SLA, limites de concurrence et procédure de révocation
  sont documentés.
- [ ] Les clés, tokens et identifiants sont dans Secret Manager ou la console
  du fournisseur ; aucune clé privée n’est embarquée dans l’app.
- [ ] La configuration de production refuse tout fournisseur non validé.
- [ ] La CMP, la publicité, les achats et les déclarations App Store/Google Play
  correspondent au comportement réel de la build.
- [ ] Le kill switch fournisseur a été testé en staging et le fallback est
  documenté.

## Dossier de preuve obligatoire

Pour chaque fournisseur, archiver une fiche selon
[`provider-evidence-template.md`](provider-evidence-template.md), puis les
documents dans un coffre versionné hors du dépôt si leur contenu est
confidentiel. Ne jamais committer de clé, contrat confidentiel ou donnée
personnelle.

La release doit référencer un identifiant de dossier, une date de vérification,
un hash ou numéro de version du document et le nom du validateur.

## Contrôle avant publication

Le responsable release doit vérifier le registre
[`provider-register.md`](provider-register.md), le présent gate et la checklist
matériel de release. En cas de fournisseur non validé, l’action correcte est de
le désactiver ou de revenir aux fixtures/cache autorisés, pas de publier avec
une attribution seule.
