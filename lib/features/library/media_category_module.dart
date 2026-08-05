import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';

class MediaCategoryModule extends Module {
  MediaCategoryModule(this.category);

  final MediaLibraryCategory category;

  @override
  void routes(r) {
    r.child('/', child: (_) {
      final runtime = MediaCategoryRuntime(
        localController: Modular.get<LocalController>(),
        videoController: Modular.get<LocalVideoController>(),
        workTmdbRepository: Modular.get<CloudWorkTmdbRepository>(),
        hiddenVideoRepository: Modular.get<CloudHiddenVideoRepository>(),
        settings: Modular.get<TypedSettings>(),
        navigateToPlayer: () async {
          await Modular.to.pushNamed('/video/');
        },
      );
      return MediaCategoryPage(
        category: category,
        initialize: runtime.initialize,
        libraryProvider: () => runtime.library,
        onPlayEpisode: runtime.playEpisode,
        onHideEpisodes: runtime.hideEpisodes,
      );
    });
  }
}
