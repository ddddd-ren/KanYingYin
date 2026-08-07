import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/features/tv/presentation/tv_back_shortcut_scope.dart';
import 'package:kanyingyin/platform/android/android_system_ui_surface.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_shell_host.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/theme/app_theme.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:provider/provider.dart';

const Color _fallbackThemeColor = AppTheme.brandBlue;

/// 将持久化主题色转换为应用主题颜色，不访问平台或存储。
Color parseStoredThemeColor(Object? storedValue) {
  if (storedValue == null || storedValue == 'default') {
    return _fallbackThemeColor;
  }

  int? colorValue;
  if (storedValue is int) {
    colorValue = storedValue;
  } else if (storedValue is String) {
    final normalized = storedValue.trim().replaceFirst(
          RegExp(r'^0x', caseSensitive: false),
          '',
        );
    colorValue = int.tryParse(normalized, radix: 16);
  }

  if (colorValue == null || colorValue < 0 || colorValue > 0xFFFFFFFF) {
    return _fallbackThemeColor;
  }
  return Color(colorValue);
}

class AppWidget extends StatefulWidget {
  const AppWidget({
    super.key,
    required this.capabilities,
  });

  final AppPlatformCapabilities capabilities;

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> {
  Box<Object?> setting = GStorage.setting;

  @override
  void initState() {
    super.initState();
    Modular.setObservers([AppDialog.observer]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context);
    _applyStoredThemePreferences(themeProvider);
  }

  void _applyStoredThemePreferences(ThemeProvider themeProvider) {
    final storedThemeMode =
        setting.get(SettingBoxKey.themeMode, defaultValue: 'system');
    final themeMode = switch (storedThemeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    themeProvider.setThemeMode(themeMode, notify: false);

    final useSystemFont = setting.getTyped<bool>(
      SettingBoxKey.useSystemFont,
      defaultValue: false,
    );
    themeProvider.setFontFamily(useSystemFont, notify: false);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final storedThemeColor =
        setting.get(SettingBoxKey.themeColor, defaultValue: 'default');
    final color = parseStoredThemeColor(storedThemeColor);
    final oledEnhance = setting.getTyped<bool>(
      SettingBoxKey.oledEnhance,
      defaultValue: false,
    );
    final defaultDarkTheme = AppTheme.dark(
      fontFamily: themeProvider.currentFontFamily,
      seedColor: color,
    );
    final defaultLightTheme = AppTheme.light(
      fontFamily: themeProvider.currentFontFamily,
      seedColor: color,
    );
    final effectiveDarkTheme = oledEnhance
        ? AppTheme.withOledBackground(defaultDarkTheme)
        : defaultDarkTheme;
    final app = MaterialApp.router(
      title: AppIdentity.displayName,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'CN',
        ),
      ],
      locale: const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      ),
      theme: defaultLightTheme,
      darkTheme: effectiveDarkTheme,
      themeMode: themeProvider.themeMode,
      routerConfig: Modular.routerConfig,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        return TvBackShortcutScope(
          enabled: widget.capabilities.isAndroidTv,
          child: AndroidSystemUiSurface(
            capabilities: widget.capabilities,
            child: content,
          ),
        );
      },
    );
    return AppShellHost(
      capabilities: widget.capabilities,
      child: app,
    );
  }
}
