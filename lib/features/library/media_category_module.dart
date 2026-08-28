import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';

class MediaCategoryModule extends Module {
  MediaCategoryModule(this.category);

  final MediaLibraryCategory category;

  @override
  void routes(r) {
    r.child('/', child: (_) {
      final cloudController = Modular.get<CloudResourcesController>();
      final runtime = MediaCategoryRuntime(
        localController: Modular.get<LocalController>(),
        videoController: Modular.get<LocalVideoController>(),
        refreshCloudLibrary: cloudController.reloadMediaLibrarySnapshot,
        ensureCloudLibrary: cloudController.ensureMediaLibrarySnapshot,
        cloudLibraryProvider: () => cloudController.mediaLibrarySnapshot,
        hideCloudEpisodes: cloudController.hideMediaLibraryEpisodes,
        settings: Modular.get<TypedSettings>(),
        navigateToPlayer: () async {
          await Modular.to.pushNamed('/video/');
        },
      );
      return MediaCategoryPage(
        category: category,
        initialize: runtime.initialize,
        refresh: runtime.refresh,
        libraryProvider: () => runtime.library,
        onPlayEpisode: runtime.playEpisode,
        onHideEpisodes: runtime.hideEpisodes,
        libraryListenable: cloudController.mediaLibrarySnapshotListenable,
      );
    });
  }
}
