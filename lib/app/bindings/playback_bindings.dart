import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/player/application/embedded_track_language_preferences.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';
import 'package:kanyingyin/features/player/application/truehd_fallback_policy.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';

/// 注册本地与网盘共用的播放器依赖。
void registerPlaybackBindings(Injector i) {
  i.addSingleton<LocalVideoController>(LocalVideoController.new);
  i.addSingleton<IVideoPageController>(
    () => Modular.get<LocalVideoController>(),
  );
  i.addSingleton<SubtitlePreferences>(SubtitlePreferences.new);
  i.addSingleton<EmbeddedTrackLanguagePreferences>(
    EmbeddedTrackLanguagePreferences.new,
  );
  i.addSingleton<TrueHdFallbackPolicy>(TrueHdFallbackPolicy.new);
  i.addSingleton<PlayerController>(
    () => PlayerController(
      subtitlePreferences: Modular.get<SubtitlePreferences>(),
      trackLanguagePreferences: Modular.get<EmbeddedTrackLanguagePreferences>(),
      trueHdFallbackPolicy: Modular.get<TrueHdFallbackPolicy>(),
    ),
  );
}
