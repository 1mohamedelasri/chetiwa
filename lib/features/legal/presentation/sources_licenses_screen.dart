import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/chetiwa_tokens.dart';
import '../../../core/l10n/chetiwa_localizations.dart';

final class SourcesLicensesScreen extends StatelessWidget {
  const SourcesLicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(strings.sourcesLicenses)),
      body: ListView(
        padding: const EdgeInsets.all(ChetiwaSpacing.x6),
        children: [
          Text(
            strings.sourcesLicensesIntro,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ChetiwaColors.textSecondary,
            ),
          ),
          const SizedBox(height: ChetiwaSpacing.x5),
          _SourceTile(
            name: 'Open-Meteo',
            purpose: strings.sourceOpenMeteoPurpose,
            url: 'https://open-meteo.com/',
          ),
          _SourceTile(
            name: 'LibreWXR',
            purpose: strings.sourceRainViewerPurpose,
            url: 'https://github.com/JoshuaKimsey/LibreWXR',
          ),
          _SourceTile(
            name: 'Google Maps Platform',
            purpose: strings.sourceGoogleMapsPurpose,
            url: 'https://cloud.google.com/maps-platform/terms',
          ),
          const SizedBox(height: ChetiwaSpacing.x5),
          Text(
            strings.sourcesLicensesNotice,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: ChetiwaColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

final class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.name,
    required this.purpose,
    required this.url,
  });

  final String name;
  final String purpose;
  final String url;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(name),
      subtitle: Text(purpose),
      trailing: const Icon(Icons.open_in_new_rounded),
      onTap: () => launchUrl(Uri.parse(url)),
    ),
  );
}
