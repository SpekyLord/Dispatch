import 'package:flutter/material.dart';

const _warmSeed = Color(0xFFA14B2F);
const _warmBackground = Color(0xFFFDF7F2);
const _warmSurface = Color(0xFFFFF8F3);
const _warmBorder = Color(0xFFE7D1C6);
const _ink = Color(0xFF4E433D);
const _mutedInk = Color(0xFF7A6B63);
const _coolAccent = Color(0xFF1695D3);

ThemeData buildDispatchLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _warmSeed,
      secondary: _coolAccent,
      brightness: Brightness.light,
      surface: _warmSurface,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: _warmBackground,
    cardTheme: const CardThemeData(
      color: _warmSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: _warmBorder),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _warmBackground,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: _ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: const BorderSide(color: _warmBorder),
      backgroundColor: const Color(0xFFF7EADF),
      labelStyle: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _warmBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _warmBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _warmSeed, width: 1.4),
      ),
      labelStyle: const TextStyle(color: _mutedInk),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _warmSeed,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _ink,
        side: const BorderSide(color: _warmBorder),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _warmSeed,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        color: _ink,
        fontWeight: FontWeight.w700,
        height: 1.05,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        color: _ink,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        color: _ink,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        color: _ink,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(color: _ink, height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: _mutedInk,
        height: 1.45,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        color: _ink,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}

ThemeData buildDispatchDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _warmSeed,
      secondary: _coolAccent,
      brightness: Brightness.dark,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF181513),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF181513),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF23201D),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Color(0xFF3A342F)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF23201D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3A342F)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3A342F)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD38A68), width: 1.4),
      ),
    ),
  );
}
