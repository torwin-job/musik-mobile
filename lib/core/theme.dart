import 'package:flutter/material.dart';

class MusikColors {
  static const bg = Color(0xFF100C0A);
  static const bg2 = Color(0xFF1A1410);
  static const fg = Color(0xFFF7F0E8);
  static const muted = Color(0xFFA89888);
  static const accent = Color(0xFFE07A3A);
  static const accent2 = Color(0xFF3D8F7A);
  static const line = Color(0xFF2C241C);
}

ThemeData buildMusikTheme() {
  const display = 'Syne';
  const body = 'Manrope';

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: MusikColors.bg,
    fontFamily: body,
    colorScheme: const ColorScheme.dark(
      surface: MusikColors.bg2,
      primary: MusikColors.accent,
      secondary: MusikColors.accent2,
      onPrimary: MusikColors.bg,
      onSurface: MusikColors.fg,
      outline: MusikColors.line,
    ),
  );

  final text = base.textTheme.apply(
    bodyColor: MusikColors.fg,
    displayColor: MusikColors.fg,
    fontFamily: body,
  );

  TextStyle displayStyle(TextStyle? s, {FontWeight? w, double? size}) =>
      (s ?? const TextStyle()).copyWith(
        fontFamily: display,
        fontWeight: w,
        fontSize: size,
        color: MusikColors.fg,
      );

  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: displayStyle(text.displayLarge, w: FontWeight.w800),
      displayMedium: displayStyle(text.displayMedium, w: FontWeight.w800),
      headlineLarge: displayStyle(text.headlineLarge, w: FontWeight.w800),
      headlineMedium: displayStyle(text.headlineMedium, w: FontWeight.w700),
      titleLarge: displayStyle(text.titleLarge, w: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: displayStyle(
        null,
        w: FontWeight.w800,
        size: 26,
      ).copyWith(letterSpacing: -0.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MusikColors.bg2,
      hintStyle: const TextStyle(color: MusikColors.muted, fontFamily: body),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MusikColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MusikColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MusikColors.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MusikColors.accent,
        foregroundColor: MusikColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: body,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MusikColors.fg,
        side: const BorderSide(color: MusikColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MusikColors.bg2.withValues(alpha: 0.96),
      indicatorColor: MusikColors.accent.withValues(alpha: 0.22),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: body,
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? MusikColors.fg : MusikColors.muted,
        );
      }),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MusikColors.accent,
      inactiveTrackColor: MusikColors.line,
      thumbColor: MusikColors.accent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MusikColors.bg2,
      contentTextStyle: TextStyle(color: MusikColors.fg, fontFamily: body),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
