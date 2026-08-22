import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef AnalyticsCollectionUpdater = Future<void> Function(bool enabled);

/// Keeps the Firebase Analytics choice local and explicit.
///
/// No place name, coordinate, search text or weather value belongs in this
/// preference. The SDK is disabled until the person opts in from Settings.
final class AnalyticsConsentController extends ChangeNotifier {
  AnalyticsConsentController({
    required bool initiallyEnabled,
    AnalyticsCollectionUpdater? updateCollection,
  }) : _enabled = initiallyEnabled,
       _updateCollection = updateCollection ?? _setFirebaseCollectionEnabled;

  static const storageKey = 'privacy:analytics-collection-enabled';

  final AnalyticsCollectionUpdater _updateCollection;
  bool _enabled;

  bool get isEnabled => _enabled;

  static Future<void> _setFirebaseCollectionEnabled(bool enabled) =>
      FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);

  /// Returns false only when enabling the SDK itself failed.
  Future<bool> setEnabled(bool enabled) async {
    if (_enabled == enabled) return true;

    if (enabled) {
      try {
        await _updateCollection(true);
      } catch (_) {
        return false;
      }
    } else {
      // A local opt-out must take effect even if the SDK is temporarily
      // unavailable. The next launch reads the persisted false value first.
      try {
        await _updateCollection(false);
      } catch (_) {}
    }

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(storageKey, enabled);
    _enabled = enabled;
    notifyListeners();
    return true;
  }

  /// Used by “Effacer les données locales”. It also turns off collection now.
  Future<void> clear() async {
    try {
      await _updateCollection(false);
    } catch (_) {}
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
    if (!_enabled) return;
    _enabled = false;
    notifyListeners();
  }
}
