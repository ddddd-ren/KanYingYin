import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/constants.dart';

/// 看影音统一主题入口，集中维护品牌颜色和桌面控件外观。
abstract final class AppTheme {
  static const Color brandBlue = Color(0xFF78A9D4);
  static const Color lightBrandBlue = Color(0xFF416F98);
  static const Color darkBackground = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF151B24);
  static const Color darkRaisedSurface = Color(0xFF1D2632);
  static const Color lightBackground = Color(0xFFF4F6F8);
  static const Color lightRaisedSurface = Color(0xFFFFFFFF);

  static ThemeData light({String? fontFamily, Color? seedColor}) {
    final usesBrandColor = seedColor == null || seedColor == brandBlue;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor ?? brandBlue,
      brightness: Brightness.light,
    ).copyWith(
      primary: usesBrandColor ? lightBrandBlue : null,
      surface: lightBackground,
      surfaceContainerLowest: lightRaisedSurface,
      surfaceContainerLow: const Color(0xFFF0F3F6),
      surfaceContainer: const Color(0xFFE9EDF1),
      surfaceContainerHigh: const Color(0xFFE2E7EC),
      surfaceContainerHighest: const Color(0xFFD9E0E6),
    );
    return _build(
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: lightBackground,
    );
  }

  static ThemeData dark({String? fontFamily, Color? seedColor}) {
    final usesBrandColor = seedColor == null || seedColor == brandBlue;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor ?? brandBlue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: usesBrandColor ? brandBlue : null,
      surface: darkSurface,
      surfaceContainerLowest: darkBackground,
      surfaceContainerLow: const Color(0xFF111720),
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkRaisedSurface,
      surfaceContainerHighest: const Color(0xFF26313E),
    );
    return _build(
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: darkBackground,
    );
  }

  static ThemeData fromColorScheme(
    ColorScheme colorScheme, {
    String? fontFamily,
  }) {
    return _build(
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }

  static ThemeData withOledBackground(ThemeData theme) {
    const background = Color(0xFF000000);
    return theme.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: theme.colorScheme.copyWith(
        surfaceContainerLowest: background,
      ),
    );
  }

  static ThemeData _build({
    required ColorScheme colorScheme,
    required String? fontFamily,
    required Color scaffoldBackgroundColor,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }
}
