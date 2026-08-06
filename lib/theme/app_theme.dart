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

  // 暖色调深色主题变体
  static const Color warmDarkBackground = Color(0xFF1A1816);
  static const Color warmDarkSurface = Color(0xFF232220);
  static const Color warmDarkRaisedSurface = Color(0xFF2C2A27);

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
    final textTheme = _buildTextTheme(fontFamily);
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      textTheme: textTheme,
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
    );
    return base.copyWith(
      appBarTheme: AppBarThemeData(
        backgroundColor:
            colorScheme.surfaceContainerLow.withValues(alpha: 0.82),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // 从 8 增加到 12
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            colorScheme.surfaceContainerHigh.withValues(alpha: 0.86),
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), // 从 12 增加到 16
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), // 从 8 增加到 12
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // 从 8 增加到 12
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        elevation: 0,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // 从 8 增加到 12
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8), // 从 6 增加到 8
        ),
        textStyle: base.textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  /// 构建优化的文本主题，提升行高和层级清晰度
  static TextTheme _buildTextTheme(String? fontFamily) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 57,
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: -0.25,
      ),
      displayMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 45,
        fontWeight: FontWeight.w400,
        height: 1.2,
      ),
      displaySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 36,
        fontWeight: FontWeight.w400,
        height: 1.2,
      ),
      headlineLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.5,
        letterSpacing: 0.15,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.5,
        letterSpacing: 0.1,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
        letterSpacing: 0.5,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
        letterSpacing: 0.25,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0.4,
      ),
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0.5,
      ),
    );
  }
}
