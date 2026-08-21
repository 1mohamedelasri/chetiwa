import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChetiwaLanguage { system, french, english }

enum TemperatureUnit { celsius, fahrenheit }

final class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({bool persist = true}) : _persist = persist {
    if (persist) unawaited(_restore());
  }

  static const _themeKey = 'appearance.theme_mode';
  static const _languageKey = 'appearance.language';
  static const _temperatureUnitKey = 'weather.temperature_unit';

  final bool _persist;
  ThemeMode _themeMode = ThemeMode.system;
  ChetiwaLanguage _language = ChetiwaLanguage.french;
  TemperatureUnit _temperatureUnit = TemperatureUnit.celsius;

  ThemeMode get themeMode => _themeMode;
  ChetiwaLanguage get language => _language;
  TemperatureUnit get temperatureUnit => _temperatureUnit;
  Locale? get locale => switch (_language) {
    ChetiwaLanguage.system => null,
    ChetiwaLanguage.french => const Locale('fr'),
    ChetiwaLanguage.english => const Locale('en'),
  };

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    if (_persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_themeKey, value.name);
    }
  }

  Future<void> setLanguage(ChetiwaLanguage value) async {
    if (_language == value) return;
    _language = value;
    notifyListeners();
    if (_persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_languageKey, value.name);
    }
  }

  Future<void> setTemperatureUnit(TemperatureUnit value) async {
    if (_temperatureUnit == value) return;
    _temperatureUnit = value;
    notifyListeners();
    if (_persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_temperatureUnitKey, value.name);
    }
  }

  /// Restores the local-only presentation preferences after a privacy reset.
  Future<void> clear() async {
    _themeMode = ThemeMode.system;
    _language = ChetiwaLanguage.french;
    _temperatureUnit = TemperatureUnit.celsius;
    notifyListeners();
    if (!_persist) return;
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_themeKey),
      preferences.remove(_languageKey),
      preferences.remove(_temperatureUnitKey),
    ]);
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final themeName = preferences.getString(_themeKey);
    final languageName = preferences.getString(_languageKey);
    final temperatureUnitName = preferences.getString(_temperatureUnitKey);
    _themeMode = ThemeMode.values.firstWhere(
      (value) => value.name == themeName,
      orElse: () => ThemeMode.system,
    );
    _language = ChetiwaLanguage.values.firstWhere(
      (value) => value.name == languageName,
      orElse: () => ChetiwaLanguage.french,
    );
    _temperatureUnit = TemperatureUnit.values.firstWhere(
      (value) => value.name == temperatureUnitName,
      orElse: () => TemperatureUnit.celsius,
    );
    notifyListeners();
  }
}
