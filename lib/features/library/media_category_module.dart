import 'dart:async';
import 'package:kanyingyin/features/library/application/media_ai_classifier.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/library/application/library_ports.dart';

class MediaCategoryModule extends Module {
  MediaCategoryModule(this.category);

  MediaCategoryModule.myLibrary() : category = null;

  final MediaLibraryCategory? category;

  @override
  void routes(r) {
    r.child('/', child: (_) {
      final localLibrary = Modular.get<LocalLibraryPort>();
      final cloudLibrary = Modular.get<CloudLibraryPort>();
      final runtime = MediaCategoryRuntime(
        includeUnavailable: category == null,
        localLibrary: localLibrary,
        cloudLibrary: cloudLibrary,
        playback: Modular.get<PlaybackPort>(),
        settings: Modular.get<TypedSettings>(),
        navigateToPlayer: () async {
          await Modular.to.pushNamed('/video/');
        },
      );
      return MediaCategoryPage(
        category: category,
        initialize: () async {
          await runtime.initialize();
          if (category != null) {
            unawaited(Modular.get<MediaAiClassifier>()
                .process(() => runtime.library));
          }
        },
        refresh: runtime.refresh,
        libraryProvider: () => runtime.library,
        onPlayEpisode: runtime.playEpisode,
        onHideEpisodes: runtime.hideEpisodes,
        userStatesProvider: () => runtime.userStates,
        onUserStateChanged: runtime.saveUserState,
        reconcileUserStates: runtime.reconcileUserStates,
        onRelinkUserState: runtime.relinkUserState,
        watchStatesProvider: () => runtime.watchStates,
        onWatchedChanged: runtime.setWatched,
        classificationModeProvider: () => runtime.classificationMode,
        onDispose: runtime.dispose,
        libraryListenable: Listenable.merge([
          cloudLibrary.changes,
          runtime,
        ]),
      );
    });
  }
}
