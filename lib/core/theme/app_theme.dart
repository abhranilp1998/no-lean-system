import 'package:flutter/material.dart';

import 'no_lean_visuals.dart';

const ink = Color(0xFF05060A);
const panel = Color(0xFF0B0F1A);
const panelRaised = Color(0xFF111726);
const cyan = Color(0xFF4DE8FF);
const magenta = Color(0xFFFF3DAF);
const purple = Color(0xFF9A5CFF);
const toxic = Color(0xFFB5FF5E);
const muted = Color(0xFF7B879E);
const red = Color(0xFFFF456A);

ThemeData buildNoLeanTheme({
  bool highContrast = false,
  bool reduceMotion = false,
  double effectScale = 1,
}) {
  final base = ThemeData.dark(useMaterial3: true);
  final background = highContrast ? Colors.black : ink;
  final surface = highContrast ? const Color(0xFF050912) : panel;
  final raisedSurface = highContrast ? const Color(0xFF0C1422) : panelRaised;
  final secondaryText = highContrast ? const Color(0xFFC4D3EC) : muted;
  final visuals = NoLeanVisuals(
    highContrast: highContrast,
    reduceMotion: reduceMotion,
    effectScale: effectScale,
    secondaryTextColor: secondaryText,
  );

  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.dark(
      primary: cyan,
      secondary: magenta,
      surface: surface,
      error: red,
      onSurface: Colors.white,
      onSurfaceVariant: secondaryText,
      outline: highContrast ? const Color(0xFF7394B8) : muted,
    ),
    textTheme: base.textTheme
        .apply(fontFamily: 'NoLeanMono')
        .apply(bodyColor: Colors.white, displayColor: Colors.white),
    primaryTextTheme: base.primaryTextTheme
        .apply(fontFamily: 'NoLeanMono')
        .apply(bodyColor: Colors.white, displayColor: Colors.white),
    splashFactory: reduceMotion
        ? NoSplash.splashFactory
        : InkSparkle.splashFactory,
    extensions: [visuals],
    pageTransitionsTheme: reduceMotion
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoMotionPageTransitionsBuilder(),
              TargetPlatform.fuchsia: _NoMotionPageTransitionsBuilder(),
              TargetPlatform.iOS: _NoMotionPageTransitionsBuilder(),
              TargetPlatform.linux: _NoMotionPageTransitionsBuilder(),
              TargetPlatform.macOS: _NoMotionPageTransitionsBuilder(),
              TargetPlatform.windows: _NoMotionPageTransitionsBuilder(),
            },
          )
        : base.pageTransitionsTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: raisedSurface.withValues(alpha: highContrast ? .96 : .8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: cyan.withValues(alpha: highContrast ? .52 : .18),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: cyan.withValues(alpha: highContrast ? .52 : .18),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cyan, width: highContrast ? 2 : 1),
      ),
      labelStyle: TextStyle(color: secondaryText),
      hintStyle: TextStyle(color: secondaryText),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface.withValues(alpha: highContrast ? 1 : .96),
      indicatorColor: cyan.withValues(alpha: highContrast ? .28 : .15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: cyan);
        }
        return IconThemeData(color: secondaryText);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? Colors.white : secondaryText,
          fontFamily: 'NoLeanMono',
          fontSize: 11,
          fontWeight: selected || highContrast
              ? FontWeight.w700
              : FontWeight.w500,
          letterSpacing: .45,
        );
      }),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: displayFont(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      contentTextStyle: TextStyle(
        color: highContrast ? Colors.white : const Color(0xFFE9F0FF),
        fontFamily: 'NoLeanMono',
        height: 1.4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cyan.withValues(alpha: highContrast ? .72 : .3),
          width: highContrast ? 1.5 : 1,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: raisedSurface,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: 'NoLeanMono',
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      actionTextColor: cyan,
      closeIconColor: Colors.white,
      behavior: SnackBarBehavior.floating,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: cyan.withValues(alpha: highContrast ? .78 : .46),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: secondaryText.withValues(alpha: highContrast ? .48 : .2),
    ),
  );
}

class _NoMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoMotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
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
