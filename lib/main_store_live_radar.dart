import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app/app.dart';
import 'features/forecast/application/weather_section_cubit.dart';
import 'firebase_options.dart';

/// Live-provider Radar entry point used only to capture an honest Store image.
/// Production continues to start on Graph through [main.dart].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  runApp(
    const ChetiwaApp(
      analyticsConsent: false,
      initialWeatherSection: WeatherSection.radar,
    ),
  );
}
