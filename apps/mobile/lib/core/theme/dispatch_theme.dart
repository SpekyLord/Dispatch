import 'package:flutter/material.dart';
import 'package:dispatch_mobile/core/theme/dispatch_colors.dart';

// ── "The Calm Authority" Design System ──────────────────────────────────────
// Organic Functionalism: Swiss grid logic + editorial warmth.
// No-Line Rule: boundaries via tonal shifts, never 1px borders.
// Glassmorphism: frosted navbars, ambient shadows.

ThemeData buildDispatchLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      secondary: secondary,
      tertiary: tertiary,
      error: error,
      brightness: Brightness.light,
      surface: surface,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: background,

    // ── Cards: No-Line Rule — tonal fill, no border ──────────────────
    cardTheme: const CardThemeData(
      color: surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),

    // ── AppBar: editorial clean ──────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),

    // ── Chips: pill-shaped, tonal fill, no border ────────────────────
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide.none,
      backgroundColor: surfaceContainerLow,
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        color: onSurfaceVariant,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),

    // ── Input: filled, no border, focus via tonal shift ──────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary.withValues(alpha: 0.15), width: 1),
      ),
      labelStyle: const TextStyle(fontFamily: 'Inter', color: onSurfaceVariant),
    ),

    // ── Buttons: CTA Soul — gradient feel, xl radius ─────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: BorderSide(color: outlineVariant.withValues(alpha: 0.15)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),

    // ── Bottom Nav: glassmorphic styling handled in widget ───────────
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: primary,
      unselectedItemColor: onSurface.withValues(alpha: 0.5),
      selectedLabelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 1.0,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 1.0,
      ),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),

    // ── FAB ──────────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),

    // ── Typography: Top-Heavy editorial voice ────────────────────────
    textTheme: base.textTheme.copyWith(
      // Display-LG: Critical status (e.g., "SAFE")
      displayLarge: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 56,
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
        height: 1.0,
      ),
      // Headline-SM: Section headers — editorial magazine feel
      headlineSmall: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.5,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      // Body-MD: Instructional content workhorse
      bodyLarge: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontSize: 14,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        color: onSurfaceVariant,
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'Inter',
        color: onSurfaceVariant,
        fontSize: 12,
        height: 1.4,
      ),
      // Label-SM: uppercase metadata tags
      labelSmall: const TextStyle(
        fontFamily: 'Inter',
        color: onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'Inter',
        color: onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}

ThemeData buildDispatchDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      secondary: secondary,
      tertiary: tertiary,
      error: error,
      brightness: Brightness.dark,
      surface: darkSurface,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: darkBackground,

    cardTheme: const CardThemeData(
      color: darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: darkInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),

    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide.none,
      backgroundColor: darkSurfaceContainer,
      labelStyle: const TextStyle(
        fontFamily: 'Inter',
        color: darkMutedInk,
        fontWeight: FontWeight.w600,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: darkPrimaryAccent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      labelStyle: const TextStyle(fontFamily: 'Inter', color: darkMutedInk),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: darkPrimaryAccent,
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkInk,
        side: BorderSide(color: darkBorder.withValues(alpha: 0.5)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: darkPrimaryAccent,
      unselectedItemColor: darkInk.withValues(alpha: 0.5),
      selectedLabelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 1.0,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 1.0,
      ),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),

    textTheme: base.textTheme.copyWith(
      displayLarge: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 56,
        fontWeight: FontWeight.w800,
        letterSpacing: -2,
        height: 1.0,
      ),
      headlineSmall: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.5,
      ),
      titleLarge: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontSize: 14,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        color: darkMutedInk,
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'Inter',
        color: darkMutedInk,
        fontSize: 12,
        height: 1.4,
      ),
      labelSmall: const TextStyle(
        fontFamily: 'Inter',
        color: darkMutedInk,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'Inter',
        color: darkInk,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );
}
