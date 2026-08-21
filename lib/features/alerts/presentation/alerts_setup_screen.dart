import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/chetiwa_tokens.dart';
import '../../../core/notifications/notification_permission_gateway.dart';
import '../../../core/location/active_location_controller.dart';
import '../application/alert_preferences_controller.dart';
import '../data/chetiwa_alert_api.dart';
import '../../analytics/application/analytics_tracker.dart';

final class AlertsSetupScreen extends StatefulWidget {
  const AlertsSetupScreen({super.key});

  @override
  State<AlertsSetupScreen> createState() => _AlertsSetupScreenState();
}

final class _AlertsSetupScreenState extends State<AlertsSetupScreen> {
  NotificationAuthorization? _authorization;
  var _loadingAuthorization = true;

  @override
  void initState() {
    super.initState();
    _refreshAuthorization();
  }

  Future<void> _refreshAuthorization() async {
    final authorization = await context
        .read<NotificationPermissionGateway>()
        .status();
    if (!mounted) return;
    setState(() {
      _authorization = authorization;
      _loadingAuthorization = false;
    });
  }

  Future<void> _toggleAlerts(bool enable) async {
    if (!enable) {
      await _setAlertsEnabled(false);
      return;
    }

    final gateway = context.read<NotificationPermissionGateway>();
    final status = _authorization ?? await gateway.status();
    if (!mounted) return;
    if (status.canSend) {
      await _setAlertsEnabled(true);
      return;
    }
    if (status == NotificationAuthorization.permanentlyDenied ||
        status == NotificationAuthorization.restricted) {
      await gateway.openSettings();
      await _refreshAuthorization();
      return;
    }

    final shouldRequest = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const SafeArea(
        child: SingleChildScrollView(child: _PermissionExplanationSheet()),
      ),
    );
    if (shouldRequest != true || !mounted) return;

    final result = await gateway.requestPermission();
    if (!mounted) return;
    setState(() => _authorization = result);
    if (result.canSend) {
      await _setAlertsEnabled(true);
    }
  }

  Future<void> _setAlertsEnabled(bool enabled) async {
    await context.read<AlertPreferencesController>().setEnabled(enabled);
    if (mounted) {
      final analytics = context.read<AnalyticsTracker?>();
      if (analytics != null) {
        unawaited(analytics.alertPreferenceChanged(enabled));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Consumer<AlertPreferencesController>(
      builder: (context, preferences, _) => Scaffold(
        appBar: AppBar(title: const Text('Smart Rain Alerts')),
        body: ListView(
          padding: const EdgeInsets.all(ChetiwaSpacing.x6),
          children: [
            _IntroCard(colors: colors),
            const SizedBox(height: ChetiwaSpacing.x6),
            _Card(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    key: const Key('smart-alerts-enabled-switch'),
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Prévenir avant la pluie'),
                    subtitle: Text(_authorizationText()),
                    value: preferences.enabled,
                    onChanged: _loadingAuthorization ? null : _toggleAlerts,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Lieu'),
                    subtitle: Consumer<ActiveLocationController>(
                      builder: (context, location, _) => Text(
                        location.location == null
                            ? 'Lieu principal · chargement…'
                            : location.location!.isCurrentDevicePosition
                            ? '${location.location!.label} · temporaire, non enregistrée'
                            : '${location.location!.label} · lieu principal',
                      ),
                    ),
                    trailing: const Icon(Icons.lock_outline, size: 18),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ChetiwaSpacing.x6),
            Text(
              'RÉGLER L’ALERTE',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: ChetiwaSpacing.x3),
            _Card(
              child: IgnorePointer(
                ignoring: !preferences.enabled,
                child: Opacity(
                  opacity: preferences.enabled ? 1 : .45,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('Me prévenir'),
                        subtitle: Text(
                          '${preferences.leadMinutes} minutes avant',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Slider(
                          key: const Key('alert-lead-time-slider'),
                          value: preferences.leadMinutes.toDouble(),
                          min: 5,
                          max: 60,
                          divisions: 11,
                          label: '${preferences.leadMinutes} min',
                          onChanged: (value) =>
                              preferences.setLeadMinutes(value.round()),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.thunderstorm_outlined),
                        title: const Text('Intensité minimale'),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SegmentedButton<RainAlertIntensity>(
                            segments: const [
                              ButtonSegment(
                                value: RainAlertIntensity.light,
                                label: Text('Faible'),
                              ),
                              ButtonSegment(
                                value: RainAlertIntensity.moderate,
                                label: Text('Modérée'),
                              ),
                              ButtonSegment(
                                value: RainAlertIntensity.heavy,
                                label: Text('Forte'),
                              ),
                            ],
                            selected: {preferences.minimumIntensity},
                            showSelectedIcon: false,
                            onSelectionChanged: (value) =>
                                preferences.setMinimumIntensity(value.first),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile.adaptive(
                        key: const Key('quiet-hours-switch'),
                        secondary: const Icon(Icons.bedtime_outlined),
                        title: const Text('Heures silencieuses'),
                        subtitle: Text(
                          '${preferences.quietHoursStart} – ${preferences.quietHoursEnd}',
                        ),
                        value: preferences.quietHoursEnabled,
                        onChanged: preferences.setQuietHoursEnabled,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: ChetiwaSpacing.x5),
            Text(
              'Chetiwa n’enverra une alerte que si vous l’activez. Votre lieu '
              'd’alerte et vos préférences servent uniquement à calculer cette alerte.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _authorizationText() {
    if (_loadingAuthorization) return 'Vérification de l’autorisation…';
    return switch (_authorization) {
      NotificationAuthorization.authorized => 'Autorisées sur cet appareil',
      NotificationAuthorization.permanentlyDenied ||
      NotificationAuthorization.restricted =>
        'Bloquées par le système · ouvrez les réglages',
      _ =>
        'Nous demanderons votre accord seulement si vous activez cette option',
    };
  }
}

final class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(ChetiwaSpacing.x5),
    decoration: BoxDecoration(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.water_drop_outlined),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La pluie, avant qu’elle arrive.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Choisissez le délai et l’intensité qui comptent pour vous. '
                'Vous gardez le contrôle à tout moment.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(ChetiwaRadius.medium),
      border: Border.all(color: Theme.of(context).colorScheme.outline),
    ),
    child: child,
  );
}

final class _PermissionExplanationSheet extends StatelessWidget {
  const _PermissionExplanationSheet();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Autoriser les alertes pluie ?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const Text(
          'Chetiwa vous avertira avant la pluie selon le délai et le seuil que '
          'vous avez choisis. Vous pourrez désactiver ces alertes à tout moment.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('request-notification-permission-button'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continuer'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Pas maintenant'),
        ),
      ],
    ),
  );
}
