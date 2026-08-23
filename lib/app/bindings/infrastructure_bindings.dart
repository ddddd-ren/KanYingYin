import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/app_update/application/app_update_checker.dart';
import 'package:kanyingyin/features/app_update/application/windows_update_installer.dart';
import 'package:kanyingyin/features/app_update/data/github_release_client.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/features/app_update/presentation/app_update_dialog.dart';
import 'package:kanyingyin/features/app_update/presentation/app_update_flow.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/logger.dart';

/// 注册应用启动后由多个功能共享的基础设施依赖。
void registerInfrastructureBindings(
  Injector i, {
  required TmdbCredentialManager tmdbCredentialManager,
}) {
  i.addSingleton<TypedSettings>(() => TypedSettings(GStorage.setting));
  i.addSingleton<MediaRecognitionSettings>(MediaRecognitionSettings.new);
  i.addSingleton<TmdbCredentialManager>(() => tmdbCredentialManager);
  i.addSingleton<TmdbApiKeyProvider>(
    () => TmdbApiKeyProvider(userKeyReader: tmdbCredentialManager.read),
  );
  i.addSingleton<TmdbClientContextRegistry>(TmdbClientContextRegistry.new);
  i.addSingleton<ShadersController>(() => ShadersController());
  _registerAppUpdateBindings(i);
}

void _registerAppUpdateBindings(Injector i) {
  i.addSingleton<GitHubReleaseClient>(GitHubReleaseClient.new);
  i.addSingleton<AppUpdateChecker>(
    () => AppUpdateChecker(
      localVersion: SemanticVersion.parse(AppVersion.current),
      fetchLatestRelease:
          Modular.get<GitHubReleaseClient>().fetchLatestStableRelease,
    ),
  );
  i.addSingleton<DailyUpdateCheckPolicy>(
    () => DailyUpdateCheckPolicy(settings: Modular.get<TypedSettings>()),
  );
  i.addSingleton<WindowsUpdateInstaller>(WindowsUpdateInstaller.new);
  i.addSingleton<AppUpdateFlow>(
    () => AppUpdateFlow(
      capabilities: detectAppPlatform(),
      checker: Modular.get<AppUpdateChecker>(),
      policy: Modular.get<DailyUpdateCheckPolicy>(),
      showRelease: (release) async {
        await AppDialog.show<void>(
          clickMaskDismiss: false,
          builder: (_) => AppUpdateDialog(
            release: release,
            installer: Modular.get<WindowsUpdateInstaller>(),
            capabilities: detectAppPlatform(),
          ),
        );
      },
      showToast: (message) => AppDialog.showToast(message: message),
      logError: (error, stackTrace) => AppLogger().e(
        '检查 GitHub 更新失败',
        error: error,
        stackTrace: stackTrace,
      ),
    ),
  );
}
