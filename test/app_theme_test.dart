import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/theme/app_theme.dart';

void main() {
  test('默认深色主题使用银幕档案馆配色', () {
    final theme = AppTheme.dark(fontFamily: 'MiSans');

    expect(theme.scaffoldBackgroundColor, const Color(0xFF0D1117));
    expect(theme.colorScheme.primary, const Color(0xFF78A9D4));
    expect(theme.colorScheme.surface, const Color(0xFF151B24));
    expect(theme.textTheme.bodyMedium?.fontFamily, 'MiSans');
  });

  test('默认浅色主题保留品牌色并使用中性内容表面', () {
    final theme = AppTheme.light(fontFamily: 'MiSans');

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F6F8));
    expect(theme.colorScheme.primary, const Color(0xFF416F98));
    expect(theme.colorScheme.surface, const Color(0xFFF4F6F8));
  });

  test('品牌主题统一卡片和对话框圆角', () {
    final theme = AppTheme.dark(fontFamily: 'MiSans');
    final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
    final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;

    expect(cardShape.borderRadius, BorderRadius.circular(8));
    expect(dialogShape.borderRadius, BorderRadius.circular(12));
  });

  test('动态配色仍使用看影音组件和表面规范', () {
    final source = ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: Brightness.dark,
    );
    final theme = AppTheme.fromColorScheme(
      source,
      fontFamily: 'MiSans',
    );

    expect(theme.colorScheme, source);
    expect(theme.scaffoldBackgroundColor, source.surface);
    expect(theme.cardTheme.margin, EdgeInsets.zero);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'MiSans');
  });

  test('OLED 增强只把最底层背景改为纯黑', () {
    final base = AppTheme.dark(fontFamily: 'MiSans');
    final theme = AppTheme.withOledBackground(base);

    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.colorScheme.surfaceContainerLowest, Colors.black);
    expect(theme.colorScheme.surface, AppTheme.darkSurface);
    expect(theme.colorScheme.primary, AppTheme.brandBlue);
  });

  test('外观设置复用统一主题工厂', () {
    final source =
        File('lib/pages/settings/theme_settings_page.dart').readAsStringSync();

    expect(source, contains('AppTheme.light('));
    expect(source, contains('AppTheme.dark('));
    expect(source, contains('AppTheme.withOledBackground('));
    expect(source, isNot(contains('Utils.oledDarkTheme(')));
    expect(source, isNot(contains('Color(0xFF00D4AA)')));
  });
}
