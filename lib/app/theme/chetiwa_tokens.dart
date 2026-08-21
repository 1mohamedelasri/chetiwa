import 'package:flutter/material.dart';

abstract final class ChetiwaColors {
  static const backgroundPrimary = Color(0xFF09161E);
  static const backgroundSecondary = Color(0xFF0D1E27);
  static const surfacePrimary = Color(0xFF10232D);
  static const surfaceSecondary = Color(0xFF1C303B);
  static const borderDefault = Color(0xFF344A55);
  static const textPrimary = Color(0xFFF6F9FA);
  static const textSecondary = Color(0xFF8CA0AA);
  static const rainNone = Color(0xFF79DDDA);
  static const rainLight = Color(0xFF4EA7D8);
  static const rainModerate = Color(0xFF2F6EDB);
  static const rainHeavy = Color(0xFF745BC7);
  static const accentPrimary = Color(0xFF79DDDA);
  static const warning = Color(0xFFE7A43B);
  static const error = Color(0xFFFF6B6B);
}

abstract final class ChetiwaSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
}

abstract final class ChetiwaRadius {
  static const small = 10.0;
  static const medium = 16.0;
  static const large = 24.0;
  static const full = 999.0;
}

abstract final class ChetiwaElevation {
  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x3D000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

abstract final class ChetiwaMotion {
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 480);

  /// Honors the platform "reduce motion" setting for non-essential UI motion.
  static Duration accessible(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
