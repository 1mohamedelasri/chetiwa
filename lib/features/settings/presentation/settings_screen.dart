import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/chetiwa_tokens.dart';
import '../../../app/preferences/app_preferences_controller.dart';
import '../../../core/app/app_version.dart';
import '../../../core/location/coordinates.dart';
import '../../../core/location/location_repository.dart';
import '../../../core/location/active_location_controller.dart';
import '../../../core/l10n/chetiwa_localizations.dart';
import '../../alerts/application/alert_preferences_controller.dart';
import '../../alerts/application/local_rain_alert_coordinator.dart';
import '../../analytics/application/analytics_consent_controller.dart';
import '../../forecast/presentation/widgets/weather_chrome.dart';
import '../../monetization/domain/consent_repository.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  late Future<ChetiwaLocation?> _mainLocation;
  late Future<String> _appVersion;

  @override
  void initState() {
    super.initState();
    _mainLocation = context.read<LocationRepository>().getMainLocation();
    _appVersion = AppVersion.displayLabel();
  }

  Future<void> _clearMainLocation() async {
    await context.read<LocationRepository>().clearMainLocation();
    if (!mounted) return;
    context.read<ActiveLocationController>().clear();
    await context.read<LocalRainAlertCoordinator>().sync();
    if (mounted) {
      setState(() {
        _mainLocation = Future.value(null);
      });
    }
  }

  Future<void> _chooseMainLocation() async {
    final repository = context.read<LocationRepository>();
    final selected = await showChetiwaLocationPicker(
      context,
      repository: repository,
      persistAsMainLocation: true,
    );
    if (selected == null || !mounted) return;
    context.read<ActiveLocationController>().setActive(selected);
    setState(() {
      _mainLocation = Future.value(selected);
    });
    final result = await context.read<LocalRainAlertCoordinator>().sync();
    if (!mounted) return;
    final message = switch (result) {
      RainAlertSyncResult.scheduled =>
        'Lieu principal enregistré et prochaine alerte programmée.',
      RainAlertSyncResult.failed =>
        'Lieu enregistré. La météo sera resynchronisée plus tard.',
      _ => 'Lieu principal enregistré sur cet appareil.',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmClearLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.clearLocalData),
        content: Text(context.l10n.clearLocalDataDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.clearLocalDataConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _clearLocalData();
  }

  Future<void> _clearLocalData() async {
    await context.read<AnalyticsConsentController>().clear();
    if (!mounted) return;
    // Delete the server-side token and alert rules while the current private
    // installation id is still available to authenticate that deletion.
    final remoteDeleted = await context
        .read<LocalRainAlertCoordinator>()
        .deleteRemoteRegistration();
    if (!mounted) return;
    if (!remoteDeleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connexion requise pour supprimer les alertes distantes. Réessayez.',
          ),
        ),
      );
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where(
      (key) =>
          key.startsWith('locations:') ||
          key.startsWith('forecast:v2:') ||
          key.startsWith('radar:v2:') ||
          key.startsWith('privacy:'),
    );
    await Future.wait(keys.map(preferences.remove));
    if (!mounted) return;
    await context.read<AlertPreferencesController>().clear();
    if (!mounted) return;
    await context.read<AppPreferencesController>().clear();
    if (!mounted) return;
    context.read<ActiveLocationController>().clear();
    setState(() {
      _mainLocation = Future.value(null);
    });
  }

  Future<void> _changeAnalyticsConsent(bool enabled) async {
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.analyticsTitle),
          content: Text(context.l10n.analyticsEnableDetail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.close),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.analyticsEnable),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }

    final changed = await context.read<AnalyticsConsentController>().setEnabled(
      enabled,
    );
    if (!changed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.analyticsUpdateFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.l10n;
    final preferences = context.read<AppPreferencesController>();
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(strings.settings)),
        body: ListView(
          padding: const EdgeInsets.all(ChetiwaSpacing.x6),
          children: [
            Container(
              padding: const EdgeInsets.all(ChetiwaSpacing.x5),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
                border: Border.all(color: colors.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push('/subscription'),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: ChetiwaColors.surfaceSecondary,
                      child: Icon(Icons.workspace_premium_outlined),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chetiwa+',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            strings.premiumSubtitle,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ChetiwaSpacing.x8),
            _SectionTitle(strings.preferences),
            const SizedBox(height: ChetiwaSpacing.x3),
            _SettingsCard(
              children: [
                FutureBuilder<ChetiwaLocation?>(
                  future: _mainLocation,
                  builder: (context, snapshot) {
                    final location = snapshot.data;
                    return ListTile(
                      key: const Key('main-location-settings'),
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(strings.mainLocation),
                      subtitle: Text(
                        location == null
                            ? strings.chooseMainLocationHelp
                            : strings.savedOnDevice(location.label),
                      ),
                      trailing: location == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              tooltip: context.l10n.clear,
                              onPressed: _clearMainLocation,
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                      onTap: _chooseMainLocation,
                    );
                  },
                ),
                ListTile(
                  key: const Key('saved-places-settings'),
                  leading: const Icon(Icons.bookmark_outline),
                  title: const Text('Mes lieux'),
                  subtitle: const Text('Maison, travail et destinations'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/saved-places'),
                ),
                ListTile(
                  key: const Key('open-smart-alerts-settings'),
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Smart Rain Alerts'),
                  subtitle: Text(strings.smartAlertSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/alerts'),
                ),
                ListenableBuilder(
                  listenable: preferences,
                  builder: (context, _) => SwitchListTile(
                    secondary: const Icon(Icons.thermostat_outlined),
                    title: Text(strings.temperature),
                    subtitle: Text(
                      preferences.temperatureUnit == TemperatureUnit.celsius
                          ? 'Celsius'
                          : 'Fahrenheit',
                    ),
                    value:
                        preferences.temperatureUnit == TemperatureUnit.celsius,
                    onChanged: (value) => preferences.setTemperatureUnit(
                      value
                          ? TemperatureUnit.celsius
                          : TemperatureUnit.fahrenheit,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ChetiwaSpacing.x8),
            _SectionTitle(strings.appearance),
            const SizedBox(height: ChetiwaSpacing.x3),
            _SettingsCard(
              children: [
                _ChoiceTile<ThemeMode>(
                  key: const Key('theme-mode-choice'),
                  icon: Icons.contrast_rounded,
                  title: strings.appearance,
                  value: preferences.themeMode,
                  choices: {
                    ThemeMode.system: strings.system,
                    ThemeMode.light: strings.light,
                    ThemeMode.dark: strings.dark,
                  },
                  onChanged: preferences.setThemeMode,
                ),
                _ChoiceTile<ChetiwaLanguage>(
                  key: const Key('language-choice'),
                  icon: Icons.language_rounded,
                  title: strings.language,
                  value: preferences.language,
                  choices: {
                    ChetiwaLanguage.system: strings.system,
                    ChetiwaLanguage.french: strings.french,
                    ChetiwaLanguage.english: strings.english,
                  },
                  onChanged: preferences.setLanguage,
                ),
              ],
            ),
            const SizedBox(height: ChetiwaSpacing.x8),
            _SectionTitle(strings.information),
            const SizedBox(height: ChetiwaSpacing.x3),
            _SettingsCard(
              children: [
                ListenableBuilder(
                  listenable: context.read<AnalyticsConsentController>(),
                  builder: (context, _) {
                    final analytics = context
                        .read<AnalyticsConsentController>();
                    return SwitchListTile(
                      key: const Key('analytics-consent-toggle'),
                      secondary: const Icon(Icons.query_stats_outlined),
                      title: Text(strings.analyticsTitle),
                      subtitle: Text(
                        analytics.isEnabled
                            ? strings.analyticsEnabledDetail
                            : strings.analyticsDisabledDetail,
                      ),
                      value: analytics.isEnabled,
                      onChanged: _changeAnalyticsConsent,
                    );
                  },
                ),
                ListTile(
                  title: Text(strings.privacy),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
                ListTile(
                  key: const Key('ad-privacy-options'),
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('Préférences publicitaires'),
                  subtitle: const Text('Modifier le consentement publicitaire'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.read<ConsentRepository>().showPrivacyOptions(),
                ),
                ListTile(
                  title: Text(strings.terms),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/terms'),
                ),
                ListTile(
                  title: Text(strings.weatherData),
                  subtitle: Text(strings.weatherDataSources),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/sources-licenses'),
                ),
                ListTile(
                  key: const Key('clear-local-data'),
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(strings.clearLocalData),
                  subtitle: Text(strings.clearLocalDataDetail),
                  onTap: _confirmClearLocalData,
                ),
                ListTile(
                  key: const Key('app-version'),
                  title: Text(strings.version),
                  trailing: FutureBuilder<String>(
                    future: _appVersion,
                    builder: (context, snapshot) => Text(snapshot.data ?? '—'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title.toUpperCase(),
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      letterSpacing: 1.1,
    ),
  );
}

final class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    child: Column(children: children),
  );
}

final class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<T>(
          segments: choices.entries
              .map(
                (entry) => ButtonSegment<T>(
                  value: entry.key,
                  label: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(growable: false),
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    ),
  );
}
