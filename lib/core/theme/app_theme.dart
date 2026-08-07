import 'package:flutter/material.dart';

const ink = Color(0xFF05060A);
const panel = Color(0xFF0B0F1A);
const panelRaised = Color(0xFF111726);
const cyan = Color(0xFF4DE8FF);
const magenta = Color(0xFFFF3DAF);
const purple = Color(0xFF9A5CFF);
const toxic = Color(0xFFB5FF5E);
const muted = Color(0xFF7B879E);
const red = Color(0xFFFF456A);

ThemeData buildNoLeanTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: ink,
    colorScheme: const ColorScheme.dark(
      primary: cyan,
      secondary: magenta,
      surface: panel,
      error: red,
    ),
    textTheme: base.textTheme
        .apply(fontFamily: 'NoLeanMono')
        .apply(bodyColor: Colors.white, displayColor: Colors.white),
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panelRaised.withValues(alpha: .8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cyan.withValues(alpha: .18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cyan.withValues(alpha: .18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: cyan),
      ),
      labelStyle: const TextStyle(color: muted),
    ),
  );
}

const eyebrowStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.4,
);

const microStyle = TextStyle(fontSize: 9.5, color: muted, letterSpacing: .45);

TextStyle displayFont({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'NoLeanDisplay',
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  letterSpacing: letterSpacing,
);
