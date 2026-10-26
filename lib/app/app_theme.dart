import 'package:flutter/material.dart';

abstract final class KlipaColors {
  // Klipa On Air: warm off-white on blue-black ink, and a single tally light
  // reserved for what is on air and for the main action.
  static const ink = Color(0xFF111317);
  static const inkRaised = Color(0xFF1A1D23);
  static const inkHover = Color(0xFF252932);
  static const foreground = Color(0xFFF4F1EA);
  static const foregroundMuted = Color(0xFFB9B5AC);
  static const foregroundDim = Color(0xFF8C8981);
  static const tally = Color(0xFFFF5B24);
  static const onTally = Color(0xFF0B0B0C);
  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFFFC53D);
  static const live = tally;
  static const danger = Color(0xFFFF4D5E);
  static const border = Color(0x29FFFFFF);
}

ThemeData buildKlipaTheme() {
  // Controls take the neutral foreground; only filled buttons carry the tally.
  const colorScheme = ColorScheme.dark(
    primary: KlipaColors.foreground,
    onPrimary: KlipaColors.ink,
    secondary: KlipaColors.foregroundMuted,
    onSecondary: KlipaColors.ink,
    surface: KlipaColors.ink,
    onSurface: KlipaColors.foreground,
    surfaceContainerHighest: KlipaColors.inkHover,
    outline: KlipaColors.border,
    error: KlipaColors.danger,
    onError: KlipaColors.onTally,
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
        borderSide: const BorderSide(
          color: KlipaColors.foregroundMuted,
          width: 1.5,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: KlipaColors.tally,
        foregroundColor: KlipaColors.onTally,
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
