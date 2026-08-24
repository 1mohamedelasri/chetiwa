import 'package:go_router/go_router.dart';

import '../../features/forecast/presentation/screens/weather_screen.dart';
import '../../features/forecast/application/weather_section_cubit.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/alerts/presentation/alerts_setup_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/legal/presentation/legal_screen.dart';
import '../../features/legal/presentation/sources_licenses_screen.dart';
import '../../features/monetization/presentation/saved_places_screen.dart';
import '../../features/monetization/presentation/subscription_screen.dart';

GoRouter createAppRouter({
  String initialLocation = '/weather',
  WeatherSection initialWeatherSection = WeatherSection.graph,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/weather'),
    GoRoute(
      path: '/weather',
      builder: (context, state) =>
          WeatherScreen(initialSection: initialWeatherSection),
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
      builder: (context, state) => const SubscriptionScreen(),
    ),
    GoRoute(
      path: '/saved-places',
      builder: (context, state) => const SavedPlacesScreen(),
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
