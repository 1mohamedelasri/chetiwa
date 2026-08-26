import 'dart:async';
import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import '../../features/analytics/application/analytics_consent_controller.dart';
import '../../firebase_options.dart';
import '../app.dart';
import '../di/chetiwa_dependencies.dart';

typedef ChetiwaBootstrapLoader = Future<ChetiwaBootstrapData> Function();
typedef ChetiwaAppBuilder = Widget Function(ChetiwaBootstrapData data);

@immutable
final class ChetiwaBootstrapData {
  const ChetiwaBootstrapData({
    required this.firebaseAvailable,
    required this.analyticsConsent,
    required this.analyticsConsentDecided,
  });

  final bool firebaseAvailable;
  final bool analyticsConsent;
  final bool analyticsConsentDecided;
}

/// Gives Chetiwa a deterministic first frame even if a platform service hangs.
///
/// Weather and Radar remain usable in degraded mode. Push, Analytics and
/// Crashlytics are retried naturally on the next process start.
final class ChetiwaBootstrap extends StatefulWidget {
  const ChetiwaBootstrap({
    this.loader,
    this.appBuilder,
    this.firebaseTimeout = const Duration(seconds: 8),
    super.key,
  });

  final ChetiwaBootstrapLoader? loader;
  final ChetiwaAppBuilder? appBuilder;
  final Duration firebaseTimeout;

  @override
  State<ChetiwaBootstrap> createState() => _ChetiwaBootstrapState();
}

final class _ChetiwaBootstrapState extends State<ChetiwaBootstrap> {
  late final Future<ChetiwaBootstrapData> _initialization =
      widget.loader?.call() ?? _initializePlatformServices();

  Future<ChetiwaBootstrapData> _initializePlatformServices() async {
    // This is synchronous, but doing it after runApp keeps it out of the native
    // launch-screen critical path.
    tz.initializeTimeZones();

    try {
      // This is a total startup budget, not eight seconds per service.
      return await _initializeOptionalServices().timeout(
        widget.firebaseTimeout,
      );
    } on Object catch (error, stack) {
      // Do not hold the weather UI hostage to Firebase. The failure is visible
      // in debug logs and the next launch retries all optional services.
      debugPrint('Chetiwa Firebase bootstrap degraded: $error\n$stack');
      return const ChetiwaBootstrapData(
        firebaseAvailable: false,
        analyticsConsent: false,
        // Do not offer a choice that cannot be applied in this session.
        analyticsConsentDecided: true,
      );
    }
  }

  Future<ChetiwaBootstrapData> _initializeOptionalServices() async {
    // Both platform calls start together. A slow preferences channel must not
    // delay the Firebase attempt (or vice versa).
    final preferencesFuture = _loadPreferences();
    final firebaseFuture = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final results = await Future.wait<Object?>([
      preferencesFuture,
      firebaseFuture,
    ]);
    final preferences = results.first as SharedPreferences?;
    final storedConsent =
        preferences?.getBool(AnalyticsConsentController.storageKey) ?? false;
    final storedChoice =
        preferences?.containsKey(AnalyticsConsentController.storageKey) ??
        false;
    await Future.wait(<Future<void>>[
      FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(storedConsent),
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        storedConsent,
      ),
    ]);
    _installCrashHandlers();
    return ChetiwaBootstrapData(
      firebaseAvailable: true,
      analyticsConsent: storedConsent,
      analyticsConsentDecided: storedChoice,
    );
  }

  Future<SharedPreferences?> _loadPreferences() async {
    try {
      return await SharedPreferences.getInstance();
    } on Object catch (error) {
      debugPrint('Chetiwa preferences unavailable during bootstrap: $error');
      return null;
    }
  }

  void _installCrashHandlers() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (AnalyticsConsentController.runtimeCollectionEnabled) {
        unawaited(
          FirebaseCrashlytics.instance.recordFlutterFatalError(details),
        );
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (AnalyticsConsentController.runtimeCollectionEnabled) {
        unawaited(
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
        );
      }
      return false;
    };
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ChetiwaBootstrapData>(
    future: _initialization,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (data == null) return const _ChetiwaPreparationApp();
      final builder = widget.appBuilder;
      if (builder != null) return builder(data);
      return ChetiwaApp(
        dependencies: ChetiwaDependencies.live(
          firebaseAvailable: data.firebaseAvailable,
        ),
        analyticsConsent: data.analyticsConsent,
        analyticsConsentDecided: data.analyticsConsentDecided,
      );
    },
  );
}

final class _ChetiwaPreparationApp extends StatelessWidget {
  const _ChetiwaPreparationApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      key: const Key('chetiwa-bootstrap-preparation'),
      backgroundColor: const Color(0xFFF3F9F9),
      body: SafeArea(
        child: Center(
          child: Semantics(
            label: 'Chetiwa prépare la météo et le radar',
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/brand/chetiwa_app_icon_master.png',
                    width: 88,
                    height: 88,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Chetiwa',
                  style: TextStyle(
                    color: Color(0xFF08252D),
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Préparation de la météo et du radar…',
                  style: TextStyle(
                    color: Color(0xFF55717A),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF12AAA7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
