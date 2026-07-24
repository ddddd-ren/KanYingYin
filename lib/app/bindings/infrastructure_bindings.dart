import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';

/// 注册应用启动后由多个功能共享的基础设施依赖。
void registerInfrastructureBindings(
  Injector i, {
  required TmdbCredentialManager tmdbCredentialManager,
}) {
  i.addSingleton<MediaRecognitionSettings>(MediaRecognitionSettings.new);
  i.addSingleton<TmdbCredentialManager>(() => tmdbCredentialManager);
  i.addSingleton<TmdbApiKeyProvider>(
    () => TmdbApiKeyProvider(userKeyReader: tmdbCredentialManager.read),
  );
  i.addSingleton<ShadersController>(ShadersController.new);
}
