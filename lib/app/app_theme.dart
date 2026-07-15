import 'package:flutter/material.dart';

abstract final class KlipaColors {
  static const ink = Color(0xFF0E0E0E);
  static const inkRaised = Color(0xFF1A1A1A);
  static const inkHover = Color(0xFF252525);
  static const foreground = Color(0xFFE8E8E8);
  static const foregroundMuted = Color(0xFFCCCCCC);
  static const foregroundDim = Color(0xFF8C8C8C);
  static const indigo = Color(0xFF6C5CE7);
  static const success = Color(0xFF51CF66);
  static const warning = Color(0xFFFFB74D);
  static const live = Color(0xFFD32F2F);
  static const border = Color(0xFF303030);
}

ThemeData buildKlipaTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: KlipaColors.indigo,
    brightness: Brightness.dark,
    surface: KlipaColors.ink,
    error: const Color(0xFFFF6B6B),
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: KlipaColors.ink,
    fontFamily: 'Segoe UI',
    dividerColor: KlipaColors.border,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: KlipaColors.foreground,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      headlineSmall: TextStyle(
        color: KlipaColors.foreground,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: KlipaColors.foreground,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(color: KlipaColors.foregroundMuted),
      bodySmall: TextStyle(color: KlipaColors.foregroundDim),
      labelLarge: TextStyle(fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KlipaColors.inkRaised,
      hintStyle: const TextStyle(color: KlipaColors.foregroundDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: KlipaColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: KlipaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: KlipaColors.indigo, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KlipaColors.indigo,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: KlipaColors.foreground,
        minimumSize: const Size(0, 44),
        side: const BorderSide(color: KlipaColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KlipaColors.inkRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: KlipaColors.inkHover,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: KlipaColors.foreground),
    ),
  );
}
