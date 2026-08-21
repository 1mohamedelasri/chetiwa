import 'package:flutter/widgets.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const ChetiwaApp());
}
