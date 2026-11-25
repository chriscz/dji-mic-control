// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:flutter/material.dart';

/// Exact upstream DJI-Mic-Control light/dark design tokens.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.bgPanel,
    required this.bgElev,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentContrast,
    required this.accentSoft,
    required this.good,
    required this.warn,
    required this.danger,
    required this.v2Purple,
  });

  final Color bg;
  final Color bgPanel;
  final Color bgElev;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color accent;
  final Color accentContrast;
  final Color accentSoft;
  final Color good;
  final Color warn;
  final Color danger;
  final Color v2Purple;

  static const AppColors light = AppColors(
    bg: Color(0xFFF4F5F7),
    bgPanel: Color(0xFFFFFFFF),
    bgElev: Color(0xFFFBFBFC),
    border: Color(0xFFE2E4E9),
    borderStrong: Color(0xFFCFD3DA),
    text: Color(0xFF1B1D21),
    textDim: Color(0xFF6B7280),
    textFaint: Color(0xFF9AA0AA),
    accent: Color(0xFF2F7DE1),
    accentContrast: Color(0xFFFFFFFF),
    accentSoft: Color(0x1F2F7DE1),
    good: Color(0xFF21A065),
    warn: Color(0xFFD98324),
    danger: Color(0xFFD64545),
    v2Purple: Color(0xFFA855F7),
  );

  static const AppColors dark = AppColors(
    bg: Color(0xFF16181D),
    bgPanel: Color(0xFF1E2127),
    bgElev: Color(0xFF23262E),
    border: Color(0xFF2C313A),
    borderStrong: Color(0xFF3A4048),
    text: Color(0xFFE9EBEF),
    textDim: Color(0xFF9AA1AD),
    textFaint: Color(0xFF6D7682),
    accent: Color(0xFF5B9BF0),
    accentContrast: Color(0xFF0D1117),
    accentSoft: Color(0x295B9BF0),
    good: Color(0xFF37C185),
    warn: Color(0xFFE0A250),
    danger: Color(0xFFEB6A6A),
    v2Purple: Color(0xFFA855F7),
  );

  static AppColors of(BuildContext context) {
    return Theme.of(context).extension<AppColors>() ?? light;
  }

  @override
  AppColors copyWith({
    Color? bg,
    Color? bgPanel,
    Color? bgElev,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? textDim,
    Color? textFaint,
    Color? accent,
    Color? accentContrast,
    Color? accentSoft,
    Color? good,
    Color? warn,
    Color? danger,
    Color? v2Purple,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      bgPanel: bgPanel ?? this.bgPanel,
      bgElev: bgElev ?? this.bgElev,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentContrast: accentContrast ?? this.accentContrast,
      accentSoft: accentSoft ?? this.accentSoft,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      v2Purple: v2Purple ?? this.v2Purple,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bgPanel: Color.lerp(bgPanel, other.bgPanel, t)!,
      bgElev: Color.lerp(bgElev, other.bgElev, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContrast: Color.lerp(accentContrast, other.accentContrast, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      good: Color.lerp(good, other.good, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      v2Purple: Color.lerp(v2Purple, other.v2Purple, t)!,
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
    surface: c.bgPanel,
    primary: c.accent,
    onPrimary: c.accentContrast,
    error: c.danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    dividerColor: c.border,
    textTheme: Typography.englishLike2021.apply(
      bodyColor: c.text,
      displayColor: c.text,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: brightness == Brightness.dark ? const Color(0xFF111318) : const Color(0xFF1B1D21),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    extensions: <ThemeExtension<dynamic>>[c],
  );
}
