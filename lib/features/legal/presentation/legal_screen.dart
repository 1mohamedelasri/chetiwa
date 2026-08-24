import 'package:flutter/material.dart';

final class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.terms, super.key});

  final bool terms;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(terms ? 'Conditions d’utilisation' : 'Confidentialité'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: terms ? const [_TermsText()] : const [_PrivacyText()],
    ),
  );
}

final class _PrivacyText extends StatelessWidget {
  const _PrivacyText();

  @override
  Widget build(BuildContext context) => const Text(
    'Chetiwa utilise votre localisation uniquement lorsque vous choisissez « Ma position ». '
    'Elle n’est pas suivie en arrière-plan.\n\n'
    'Vos lieux et préférences restent sur votre appareil. Si vous activez les alertes, un '
    'identifiant d’installation, le token push, le lieu choisi et la règle d’alerte sont '
    'enregistrés afin d’envoyer la notification demandée.\n\n'
    'Pour afficher la météo, le radar et la carte, les coordonnées du lieu consulté transitent '
    'par Chetiwa et les fournisseurs indiqués dans les attributions.\n\n'
    'Les statistiques d’utilisation et diagnostics Firebase restent désactivés par défaut et '
    'ne peuvent être activés que dans Réglages, avec un choix réversible. « Effacer les données '
    'locales » demande aussi la suppression de l’enregistrement push distant. '
    'La politique complète doit être publiée par l’éditeur avant une distribution externe.',
  );
}

final class _TermsText extends StatelessWidget {
  const _TermsText();

  @override
  Widget build(BuildContext context) => const Text(
    'Chetiwa fournit des informations météo et radar à titre indicatif. Elles ne remplacent '
    'pas les alertes officielles ni les décisions de sécurité.\n\n'
    'Pendant la bêta, le service peut évoluer ou être interrompu. Les données peuvent être '
    'indisponibles, différées ou imprécises selon leur couverture et votre connexion.\n\n'
    'La première version garde publicité et Chetiwa+ désactivés. Si ces fonctions sont '
    'activées ultérieurement, leur prix et leurs conditions seront présentés avant achat.',
  );
}
