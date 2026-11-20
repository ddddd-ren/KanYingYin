import 'package:kanyingyin/app/startup_landing.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_service.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_ports.dart';

String readDefaultStartupPage(TypedSettings settings) {
  final value = settings.get(SettingBoxKey.defaultStartupPage,
      defaultValue: defaultStartupPage);
  if (value is String && isValidStartupPage(value)) return value;
  settings.put(SettingBoxKey.defaultStartupPage, defaultStartupPage);
  return defaultStartupPage;
}

String resolveInitialRoute({
  required String platformRoute,
  required bool isAndroidTv,
  required String Function() preferredPage,
}) {
  if (platformRoute.isNotEmpty && platformRoute != '/') return platformRoute;
  if (isAndroidTv) return '/';
  final page = preferredPage();
  StartupLanding.expectPage(page);
  return page;
}

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  final TypedSettings setting = Modular.get<TypedSettings>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  Future<void> _initializeApp() async {
    if (!mounted) return;
    if (detectAppPlatform().isAndroidTv) await _runPreloadedImport();
    if (!mounted) return;
    _startDefaultPage();
  }

  Future<void> _runPreloadedImport() async {
    final result = await Modular.get<TvPreloadImportService>().run();
    if (result.status != TvPreloadImportStatus.skipped) {
      AppLogger().i('TV 个人预置导入状态: ${result.status.name}');
    }
  }

  void _startDefaultPage() {
    final page = readDefaultStartupPage(setting);
    StartupLanding.expectPage(page);
    Modular.to.navigate(page);
  }

  @override
  Widget build(BuildContext context) => const LoadingWidget();
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
