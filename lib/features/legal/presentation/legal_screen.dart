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
    'Vos lieux enregistrés et préférences restent sur votre appareil. Vous pouvez effacer '
    'le lieu principal dans Réglages et supprimer les lieux récents dans le sélecteur.\n\n'
    'Pour afficher la météo, le radar et la carte, les coordonnées du lieu consulté peuvent '
    'être envoyées aux fournisseurs de données indiqués dans les attributions.\n\n'
    'Cette bêta n’utilise ni compte, ni publicité, ni achat, ni analytics, ni push distant. '
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
    'La version bêta actuelle ne propose ni publicité, ni abonnement, ni achat intégré.',
  );
}
