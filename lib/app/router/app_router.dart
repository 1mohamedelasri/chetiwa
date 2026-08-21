import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/chetiwa_localizations.dart';
import '../../features/forecast/presentation/screens/weather_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/alerts/presentation/alerts_setup_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/legal/presentation/legal_screen.dart';
import '../../features/legal/presentation/sources_licenses_screen.dart';

GoRouter createAppRouter() => GoRouter(
  initialLocation: '/weather',
  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/weather'),
    GoRoute(
      path: '/weather',
      builder: (context, state) => const WeatherScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/alerts',
      builder: (context, state) => const AlertsSetupScreen(),
    ),
    GoRoute(
      path: '/subscription',
      builder: (context, state) => _RoutePlaceholder(
        title: 'Chetiwa+',
        message: context.l10n.subscriptionComing,
      ),
    ),
    GoRoute(
      path: '/privacy',
      builder: (context, state) => const LegalScreen(terms: false),
    ),
    GoRoute(
      path: '/terms',
      builder: (context, state) => const LegalScreen(terms: true),
    ),
    GoRoute(
      path: '/sources-licenses',
      builder: (context, state) => const SourcesLicensesScreen(),
    ),
  ],
);

final class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );
}
