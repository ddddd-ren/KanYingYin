import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/app/bindings/app_bindings.dart';
import 'package:kanyingyin/bean/widget/image_preview.dart';
import 'package:kanyingyin/pages/init_page.dart';
import 'package:kanyingyin/pages/index_page.dart';
import 'package:kanyingyin/pages/router.dart';
import 'package:kanyingyin/pages/settings/settings_module.dart';
import 'package:kanyingyin/pages/video/video_module.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/utils/constants.dart';

class IndexModule extends Module {
  IndexModule({required this.tmdbCredentialManager});

  final TmdbCredentialManager tmdbCredentialManager;

  @override
  List<Module> get imports => menu.moduleList;

  @override
  void binds(Injector i) {
    registerApplicationBindings(
      i,
      tmdbCredentialManager: tmdbCredentialManager,
    );
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
