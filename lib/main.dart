import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app/bootstrap/chetiwa_bootstrap.dart';
import 'core/notifications/firebase_push_messaging.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Radar frames are large. A bounded process-wide image cache prevents a
  // long animation session from forcing Android/iOS into memory pressure.
  PaintingBinding.instance.imageCache
    ..maximumSize = 180
    ..maximumSizeBytes = 64 * 1024 * 1024;
  FirebaseMessaging.onBackgroundMessage(
    chetiwaFirebaseMessagingBackgroundHandler,
  );
  // Render a branded first frame immediately. Firebase and preferences are
  // initialized behind it with a timeout instead of leaving a native white
  // window on slow starts.
  runApp(const ChetiwaBootstrap());
}
