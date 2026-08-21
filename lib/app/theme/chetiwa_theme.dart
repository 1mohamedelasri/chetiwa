import 'package:flutter/material.dart';

import 'chetiwa_tokens.dart';

abstract final class ChetiwaTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: Color(0xFF087E82),
      onPrimary: Colors.white,
      surface: Color(0xFFF8FBFC),
      onSurface: Color(0xFF10232D),
      surfaceContainer: Color(0xFFE7F0F3),
      outline: Color(0xFFB8C9D0),
      error: Color(0xFFB4232C),
    );
    return _base(scheme);
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: ChetiwaColors.accentPrimary,
      onPrimary: ChetiwaColors.backgroundPrimary,
      surface: ChetiwaColors.surfacePrimary,
      onSurface: ChetiwaColors.textPrimary,
      error: ChetiwaColors.error,
    );

    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.brightness == Brightness.dark
        ? ChetiwaColors.backgroundPrimary
        : const Color(0xFFF1F6F8),
    fontFamily: 'Inter',
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(color: scheme.onSurface, fontSize: 14),
      bodySmall: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    dividerColor: scheme.outline,
    iconTheme: IconThemeData(color: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
    ),
  );
}
