import 'package:chetiwa/app/preferences/app_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'clear supprime les préférences locales et restaure les valeurs sûres',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = AppPreferencesController();

      await controller.setThemeMode(ThemeMode.dark);
      await controller.setLanguage(ChetiwaLanguage.english);
      await controller.setTemperatureUnit(TemperatureUnit.fahrenheit);
      await controller.clear();

      expect(controller.themeMode, ThemeMode.system);
      expect(controller.language, ChetiwaLanguage.french);
      expect(controller.temperatureUnit, TemperatureUnit.celsius);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
    },
  );
}
