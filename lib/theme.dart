import 'package:flutter/material.dart';

ThemeData buildLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3563E9),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      centerTitle: false,
    ),
  );
}

/// 宫格颜色（按 multiplier 着色）
Color cellColorFor(double multiplier) {
  if (multiplier >= 1.6) return const Color(0xFF2F4FE0);
  if (multiplier >= 1.5) return const Color(0xFF5170F0);
  if (multiplier >= 1.4) return const Color(0xFF6BD3F8);
  if (multiplier >= 1.3) return const Color(0xFFFFB877);
  if (multiplier >= 1.2) return const Color(0xFFFFF1B8);
  if (multiplier >= 1.1) return const Color(0xFFFFFAD6);
  return Colors.white;
}

Color cellTextColorFor(double multiplier) {
  if (multiplier >= 1.5) return Colors.white;
  return Colors.black87;
}
