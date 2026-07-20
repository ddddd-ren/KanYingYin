import 'package:kanyingyin/pages/about/about_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/settings/interface_settings.dart';
import 'package:kanyingyin/pages/settings/theme_settings_page.dart';
import 'package:kanyingyin/pages/settings/player_settings.dart';
import 'package:kanyingyin/pages/settings/displaymode_settings.dart';
import 'package:kanyingyin/pages/settings/decoder_settings.dart';
import 'package:kanyingyin/pages/settings/renderer_settings.dart';
import 'package:kanyingyin/pages/settings/super_resolution_settings.dart';
import 'package:kanyingyin/pages/settings/keyboard_settings.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/pages/settings/cloud_sources_settings.dart';
import 'package:kanyingyin/pages/settings/media_recognition_settings.dart';
import 'package:kanyingyin/pages/cloud/openlist_source_editor.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_source_editor.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_share_import_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';

final class CloudLibraryRescanException implements Exception {
  const CloudLibraryRescanException({
    required this.successCount,
    required this.totalCount,
    this.errorMessage,
  });

  final int successCount;
  final int totalCount;
  final String? errorMessage;

  @override
  String toString() {
    final message =
        errorMessage?.isNotEmpty == true ? errorMessage! : '网盘媒体库重新扫描未全部完成';
    return '$message（成功 $successCount/$totalCount）';
  }
}

void verifyCloudRescanResult({
  required int successCount,
  required int totalCount,
  String? errorMessage,
}) {
  if (successCount >= totalCount) return;
  throw CloudLibraryRescanException(
    successCount: successCount,
    totalCount: totalCount,
    errorMessage: errorMessage,
  );
}

class SettingsModule extends Module {
  @override
  void routes(r) {
    r.child("/theme", child: (_) => const ThemeSettingsPage());
    r.child(
      "/theme/display",
      child: (_) => const SetDisplayMode(),
    );
    r.child("/keyboard", child: (_) => const KeyboardSettingsPage());
    r.child("/player", child: (_) => const PlayerSettingsPage());
    r.child("/player/decoder", child: (_) => const DecoderSettings());
    r.child("/player/renderer", child: (_) => const RendererSettings());
    r.child("/interface", child: (_) => const InterfaceSettingsPage());
    r.child("/player/super", child: (_) => const SuperResolutionSettings());
    r.module("/about", module: AboutModule());
    r.child("/tmdb", child: (_) => const TmdbSettingsPage());
    r.child("/media-recognition", child: (_) {
      final localController = Modular.get<LocalController>();
      return MediaRecognitionSettingsPage(
        settings: Modular.get<MediaRecognitionSettings>(),
        onRescanLocal: () async {
          await localController.refreshLocalLibraryIndex(
            throwOnFailure: true,
          );
        },
        onRescanCloud: () async {
          final cloudController = Modular.get<CloudLibraryController>();
          final successCount = await cloudController.scanAllSources();
          await localController.reloadCloudLibraryIndex(
            throwOnFailure: true,
          );
          verifyCloudRescanResult(
            successCount: successCount,
            totalCount: cloudController.sources.length,
            errorMessage: cloudController.errorMessage,
          );
        },
      );
    });
    r.child(
      "/cloud-sources",
      child: (_) => CloudSourcesSettingsPage(
        controller: Modular.get<CloudLibraryController>(),
        onSourceDeleted: Modular.get<LocalController>().reloadCloudLibraryIndex,
        onSourceScanned:
            Modular.get<LocalController>().revealCloudLibrarySource,
      ),
    );
    r.child(
      "/cloud-sources/add",
      child: (_) => const CloudSourceTypePickerPage(),
    );
    r.child(
      "/cloud-sources/openlist/edit",
      child: (_) => OpenListSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
    r.child(
      "/cloud-sources/quark/edit",
      child: (_) => QuarkSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
    r.child(
      "/cloud-sources/quark/import",
      child: (_) => r.args.data is CloudSource
          ? QuarkShareImportPage(source: r.args.data as CloudSource)
          : const Scaffold(body: Center(child: Text('夸克来源不存在'))),
    );
    r.child(
      "/cloud-sources/edit",
      child: (_) => OpenListSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
  }
}
