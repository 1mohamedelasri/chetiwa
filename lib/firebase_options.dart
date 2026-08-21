// Generated from the Firebase configuration files supplied for Chetiwa.
// Re-run FlutterFire configuration when adding a Firebase product or platform.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;
    throw UnsupportedError('Firebase is configured only for Android and iOS.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyDTjJOdKPUF58Y3vJayuLR8NkkHXeR49DY",
    appId: "1:892383784494:android:3dc9cde5dc0c58f57179bf",
    messagingSenderId: "892383784494",
    projectId: "chetiwa",
    storageBucket: "chetiwa.firebasestorage.app",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyDMKRmcm2vNAj7Gty9Gi_9hZ6Npz9HT9EE",
    appId: "1:892383784494:ios:029a31289691d7787179bf",
    messagingSenderId: "892383784494",
    projectId: "chetiwa",
    storageBucket: "chetiwa.firebasestorage.app",
    iosBundleId: "com.ezplatforms.chetiwa",
  );
}
