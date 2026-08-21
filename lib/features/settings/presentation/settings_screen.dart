import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/chetiwa_tokens.dart';
import '../../../app/preferences/app_preferences_controller.dart';
import '../../../core/location/coordinates.dart';
import '../../../core/location/location_repository.dart';
import '../../../core/location/active_location_controller.dart';
import '../../../core/l10n/chetiwa_localizations.dart';
import '../../alerts/application/alert_preferences_controller.dart';

final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<SettingsScreen> {
  late Future<ChetiwaLocation?> _mainLocation;

  @override
  void initState() {
    super.initState();
    _mainLocation = context.read<LocationRepository>().getMainLocation();
  }

  Future<void> _clearMainLocation() async {
    await context.read<LocationRepository>().clearMainLocation();
    if (mounted) setState(() => _mainLocation = Future.value(null));
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
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where(
      (key) =>
          key.startsWith('locations:') ||
          key.startsWith('forecast:v2:') ||
          key.startsWith('radar:v2:'),
    );
    await Future.wait(keys.map(preferences.remove));
    if (!mounted) return;
    await context.read<AlertPreferencesController>().clear();
    if (!mounted) return;
    context.read<ActiveLocationController>().clear();
    setState(() => _mainLocation = Future.value(null));
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
                          ? const Text('Paris')
                          : IconButton(
                              tooltip: context.l10n.clear,
                              onPressed: _clearMainLocation,
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                    );
                  },
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
                ListTile(
                  title: Text(strings.privacy),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
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
                  title: Text(strings.version),
                  trailing: const Text('0.2.0 (MVP)'),
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
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
      border: Border.all(color: Theme.of(context).colorScheme.outline),
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
