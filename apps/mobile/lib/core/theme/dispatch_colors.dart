import 'package:flutter/material.dart';

// ── Design System: "The Calm Authority" ─────────────────────────────────────
// Based on the Editorial Utility design language. Safety Orange primary with
// warm neutrals. Tonal layering instead of borders.

// ── Primary (Safety Orange) ─────────────────────────────────────────────────
const primary = Color(0xFF904D00);
const primaryDim = Color(0xFF7F4300);
const onPrimary = Color(0xFFFFF6F2);
const primaryContainer = Color(0xFFFFDCC3);
const onPrimaryContainer = Color(0xFF7E4200);
const primaryFixed = Color(0xFFFFDCC3);
const primaryFixedDim = Color(0xFFFFCAA1);
const inversePrimary = Color(0xFFFE932C);

// ── Secondary (Neutral) ─────────────────────────────────────────────────────
const secondary = Color(0xFF605F5F);
const secondaryDim = Color(0xFF535353);
const onSecondary = Color(0xFFFBF8F8);
const secondaryContainer = Color(0xFFE4E2E1);
const onSecondaryContainer = Color(0xFF525151);

// ── Tertiary ────────────────────────────────────────────────────────────────
const tertiary = Color(0xFF5E5F5F);
const tertiaryContainer = Color(0xFFF4F4F3);
const onTertiaryContainer = Color(0xFF5A5C5B);

// ── Error ───────────────────────────────────────────────────────────────────
const error = Color(0xFF9E422C);
const errorDim = Color(0xFF5C1202);
const onError = Color(0xFFFFF7F6);
const errorContainer = Color(0xFFFE8B70);
const onErrorContainer = Color(0xFF742410);

// ── Surface hierarchy (tonal layering) ──────────────────────────────────────
const surface = Color(0xFFFCF9F8);
const surfaceDim = Color(0xFFDBDAD9);
const surfaceBright = Color(0xFFFCF9F8);
const surfaceContainerLowest = Color(0xFFFFFFFF);
const surfaceContainerLow = Color(0xFFF6F3F2);
const surfaceContainer = Color(0xFFF0EDED);
const surfaceContainerHigh = Color(0xFFEAE8E7);
const surfaceContainerHighest = Color(0xFFE4E2E2);
const surfaceVariant = Color(0xFFE4E2E2);
const surfaceTint = Color(0xFF904D00);

// ── On-surface ──────────────────────────────────────────────────────────────
const onSurface = Color(0xFF323233);
const onSurfaceVariant = Color(0xFF5F5F5F);
const onBackground = Color(0xFF323233);
const background = Color(0xFFFCF9F8);

// ── Outline ─────────────────────────────────────────────────────────────────
const outline = Color(0xFF7B7A7A);
const outlineVariant = Color(0xFFB3B2B1);

// ── Inverse ─────────────────────────────────────────────────────────────────
const inverseSurface = Color(0xFF0E0E0E);
const inverseOnSurface = Color(0xFF9E9C9C);

// ── Dark palette ────────────────────────────────────────────────────────────
const darkBackground = Color(0xFF181513);
const darkSurface = Color(0xFF23201D);
const darkSurfaceContainer = Color(0xFF2D2824);
const darkSurfaceContainerHigh = Color(0xFF3A342F);
const darkBorder = Color(0xFF3A342F);
const darkInk = Color(0xFFEDE6E0);
const darkMutedInk = Color(0xFF9E938B);
const darkPrimaryAccent = Color(0xFFFFB77C);

// ── Semantic status colors ──────────────────────────────────────────────────
const statusPending = Color(0xFFD97757);
const statusAccepted = Color(0xFF1695D3);
const statusResponding = Color(0xFF7B5E57);
const statusResolved = Color(0xFF397154);
const statusError = Color(0xFFB3261E);

// ── Legacy aliases (for screens not yet migrated) ───────────────────────────
const warmSeed = primary;
const warmBackground = background;
const warmSurface = surfaceContainerLowest;
const warmBorder = Color(0xFFE7D1C6);
const coolAccent = Color(0xFF1695D3);
const ink = onSurface;
const mutedInk = onSurfaceVariant;
const chipFill = Color(0xFFF7EADF);

// ── Hero gradient (shared across role screens + auth) ───────────────────────
const heroGradient = [
  Color(0xFFA14B2F),
  Color(0xFF7B3A25),
  Color(0xFF425E72),
];

// ── Category colors (feed) ──────────────────────────────────────────────────
Color categoryColor(String category) => switch (category) {
  'alert' => statusError,
  'warning' => statusPending,
  'safety_tip' => coolAccent,
  'update' => statusResolved,
  'situational_report' => statusResponding,
  _ => mutedInk,
};

// ── Status color helper ─────────────────────────────────────────────────────
Color statusColor(String status) => switch (status) {
  'pending' => statusPending,
  'accepted' => statusAccepted,
  'responding' => statusResponding,
  'resolved' => statusResolved,
  _ => Colors.grey,
};
