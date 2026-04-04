import 'package:flutter/material.dart';

// ── Core palette (matches dispatch_theme.dart) ──────────────────────────────
const warmSeed = Color(0xFFA14B2F);
const warmBackground = Color(0xFFFDF7F2);
const warmSurface = Color(0xFFFFF8F3);
const warmBorder = Color(0xFFE7D1C6);
const coolAccent = Color(0xFF1695D3);
const ink = Color(0xFF4E433D);
const mutedInk = Color(0xFF7A6B63);
const chipFill = Color(0xFFF7EADF);

// ── Dark palette ────────────────────────────────────────────────────────────
const darkBackground = Color(0xFF181513);
const darkSurface = Color(0xFF23201D);
const darkBorder = Color(0xFF3A342F);
const darkInk = Color(0xFFEDE6E0);
const darkMutedInk = Color(0xFF9E938B);

// ── Semantic status colors ──────────────────────────────────────────────────
const statusPending = Color(0xFFD97757);
const statusAccepted = Color(0xFF1695D3);
const statusResponding = Color(0xFF7B5E57);
const statusResolved = Color(0xFF397154);
const statusError = Color(0xFFB3261E);

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
