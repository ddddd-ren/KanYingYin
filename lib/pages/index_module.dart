import 'package:kanyingyin/pages/index_page.dart';
import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';
import 'package:kanyingyin/features/player/application/truehd_fallback_policy.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/router.dart';
import 'package:kanyingyin/pages/init_page.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/video/video_module.dart';
import 'package:kanyingyin/pages/settings/settings_module.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/bean/widget/image_preview.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';

class IndexModule extends Module {
  @override
  List<Module> get imports => menu.moduleList;

  @override
  void binds(Injector i) {
    i.addSingleton<MediaRecognitionSettings>(MediaRecognitionSettings.new);
    i.addSingleton<ILocalMediaIndexRepository>(LocalMediaIndexRepository.new);
    i.addSingleton<ILocalMediaSourceRepository>(LocalMediaSourceRepository.new);
    i.addSingleton<ILocalLibraryPreferences>(LocalLibraryPreferences.new);
    i.addSingleton<LocalLibraryMetadataCoordinator>(
        () => LocalLibraryMetadataCoordinator(
              mediaIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
            ));
    i.addSingleton<CloudMediaIndexRepository>(CloudMediaIndexRepository.new);
    i.addSingleton<CloudCredentialStore>(SecureCloudCredentialStore.new);
    i.addSingleton<CloudSourceRepository>(() => CloudSourceRepository(
          credentialStore: Modular.get<CloudCredentialStore>(),
        ));
    i.addSingleton<CloudLibraryController>(() => CloudLibraryController(
          repository: Modular.get<CloudSourceRepository>(),
          credentialStore: Modular.get<CloudCredentialStore>(),
          mediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
          mediaIndexer: CloudMediaIndexer(
            repository: Modular.get<CloudMediaIndexRepository>(),
            minRecognizedVideoSizeBytesProvider: () =>
                Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
          ),
        ));
    i.addSingleton<ILocalMediaIndexer>(() => LocalMediaIndexer(
          repository: Modular.get<ILocalMediaIndexRepository>(),
          minRecognizedVideoSizeBytesProvider: () =>
              Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
        ));

    i.addSingleton<LocalVideoController>(LocalVideoController.new);
    i.addSingleton<IVideoPageController>(
        () => Modular.get<LocalVideoController>());
    i.addSingleton<SubtitlePreferences>(SubtitlePreferences.new);
    i.addSingleton<TrueHdFallbackPolicy>(TrueHdFallbackPolicy.new);
    i.addSingleton<PlayerController>(() => PlayerController(
          subtitlePreferences: Modular.get<SubtitlePreferences>(),
          trueHdFallbackPolicy: Modular.get<TrueHdFallbackPolicy>(),
        ));
    i.addSingleton<ShadersController>(ShadersController.new);
    i.addSingleton<LocalController>(() => LocalController(
          scanner: LocalMediaScanner(
            minRecognizedVideoSizeBytesProvider: () =>
                Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
          ),
          mediaIndexer: Modular.get<ILocalMediaIndexer>(),
          preferences: Modular.get<ILocalLibraryPreferences>(),
          metadataCoordinator: Modular.get<LocalLibraryMetadataCoordinator>(),
          mediaIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
          mediaSourceRepository: Modular.get<ILocalMediaSourceRepository>(),
          cloudSourceRepository: Modular.get<CloudSourceRepository>(),
          cloudMediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
          scanCloudSource: (sourceId) async {
            await Modular.get<CloudLibraryController>().scanSource(sourceId);
          },
        ));
  }

  @override
  void routes(r) {
    r.child("/",
        child: (_) => const InitPage(),
        children: [
          ChildRoute(
            "/error",
            child: (_) => Scaffold(
              appBar: AppBar(title: const Text("看影音")),
              body: const Center(child: Text("初始化失败")),
            ),
          ),
        ],
        transition: TransitionType.noTransition);
    r.child(
      "/tab",
      child: (_) {
        return const IndexPage();
      },
      children: menu.routes,
      transition: TransitionType.fadeIn,
      duration: StyleString.fastAnimationDuration,
    );
    r.module("/video", module: VideoModule());
    r.child(
      ImageViewer.routePath,
      child: (_) {
        final args = Modular.args.data as ImageViewerRouteArgs;
        return ImageViewer(
          imageUrl: args.imageUrl,
          heroTag: args.heroTag,
        );
      },
      transition: TransitionType.fadeIn,
      duration: StyleString.animationDuration,
    );

    r.module("/settings", module: SettingsModule());
  }
}
