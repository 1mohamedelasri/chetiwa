import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app/app.dart';
import 'firebase_options.dart';
import 'features/analytics/application/analytics_consent_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final preferences = await SharedPreferences.getInstance();
  final analyticsConsent =
      preferences.getBool(AnalyticsConsentController.storageKey) ?? false;
  // Analytics remains opt-in and this setting is applied before the UI starts.
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
    analyticsConsent,
  );
  tz.initializeTimeZones();
  runApp(ChetiwaApp(analyticsConsent: analyticsConsent));
}
