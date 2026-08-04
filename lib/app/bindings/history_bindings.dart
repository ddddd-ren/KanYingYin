import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/history/application/playback_history_repository.dart';

/// 注册本地与网盘共用的观看历史服务。
void registerHistoryBindings(Injector i) {
  i.addSingleton<PlaybackHistoryRepository>(PlaybackHistoryRepository.new);
  i.addSingleton<PlaybackHistoryController>(
    () => PlaybackHistoryController(
      repository: Modular.get<PlaybackHistoryRepository>(),
    ),
  );
}
