import 'package:kanyingyin/pages/about/about_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/configuration_transfer/presentation/configuration_transfer_page.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/presentation/scraped_metadata_transfer_page.dart';
import 'package:kanyingyin/pages/settings/interface_settings.dart';
import 'package:kanyingyin/pages/settings/theme_settings_page.dart';
import 'package:kanyingyin/pages/settings/player_settings.dart';
import 'package:kanyingyin/pages/settings/player_color_settings.dart';
import 'package:kanyingyin/pages/settings/decoder_settings.dart';
import 'package:kanyingyin/pages/settings/renderer_settings.dart';
import 'package:kanyingyin/pages/settings/super_resolution_settings.dart';
import 'package:kanyingyin/pages/settings/keyboard_settings.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/pages/settings/cloud_sources_settings.dart';
import 'package:kanyingyin/pages/settings/media_recognition_settings.dart';
import 'package:kanyingyin/pages/settings/storage_settings_page.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:kanyingyin/pages/cloud/openlist_source_editor.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_source_editor.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_share_import_page.dart';
import 'package:kanyingyin/pages/cloud/baidu/baidu_source_editor.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_source_editor.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/features/settings/presentation/settings_motion.dart';
import 'package:kanyingyin/features/history/presentation/history_page.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_controller.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_file_import_coordinator.dart';
import 'package:kanyingyin/features/tv_pairing/presentation/tv_pairing_page.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';

void _child(
  RouteManager r,
  String path, {
  required ModularChild child,
}) {
  r.child(
    path,
    child: child,
    transition: TransitionType.rightToLeftWithFade,
    duration: SettingsMotion.pageDuration,
  );
}

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
    _child(
      r,
      "/storage",
      child: (_) => StorageSettingsPage(
        resolver:
            StoragePathResolver.current ?? (throw StateError('存储路径尚未初始化')),
      ),
    );
    _child(r, "/theme", child: (_) => const ThemeSettingsPage());
    _child(r, "/keyboard", child: (_) => const KeyboardSettingsPage());
    _child(r, "/player", child: (_) => const PlayerSettingsPage());
    _child(
      r,
      "/player/color",
      child: (_) => const PlayerColorSettingsPage(),
    );
    _child(r, "/player/decoder", child: (_) => const DecoderSettings());
    _child(
      r,
      "/player/renderer",
      child: (_) => const RendererSettingsPage(),
    );
    _child(r, "/interface", child: (_) => const InterfaceSettingsPage());
    _child(r, "/history", child: (_) => const HistoryPage());
    _child(
      r,
      "/player/super",
      child: (_) => const SuperResolutionSettings(),
    );
    r.module(
      "/about",
      module: AboutModule(),
      transition: TransitionType.rightToLeftWithFade,
      duration: SettingsMotion.pageDuration,
    );
    _child(
      r,
      "/tmdb/transfer",
      child: (_) => ScrapedMetadataTransferPage(
        service: Modular.get<ScrapedMetadataTransferService>(),
      ),
    );
    _child(
      r,
      "/tmdb",
      child: (_) => TmdbSettingsPage(
        credentialManager: Modular.get<TmdbCredentialManager>(),
        settings: Modular.get<TypedSettings>(),
        apiKeyProvider: Modular.get<TmdbApiKeyProvider>(),
      ),
    );
    _child(r, "/media-recognition", child: (_) {
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
    _child(
      r,
      "/cloud-sources",
      child: (_) => CloudSourcesSettingsPage(
        controller: Modular.get<CloudLibraryController>(),
        onSourceDeleted: Modular.get<LocalController>().reloadCloudLibraryIndex,
        onSourceScanned:
            Modular.get<LocalController>().revealCloudLibrarySource,
      ),
    );
    _child(
      r,
      "/cloud-sources/configuration-transfer",
      child: (_) => ConfigurationTransferPage(
        service: Modular.get<ConfigurationTransferService>(),
        onImported: Modular.get<CloudLibraryController>().load,
      ),
    );
    _child(
      r,
      "/cloud-sources/add",
      child: (_) => const CloudSourceTypePickerPage(),
    );
    _child(
      r,
      "/cloud-sources/tv-pairing",
      child: (_) => TvPairingPage(
        controller: TvPairingController(
          importer: Modular.get<ConfigurationImporter>(),
          fileImporter: TvPairingFileImportCoordinator(
            configurationTransfer: Modular.get<ConfigurationTransferService>(),
            metadataTransfer: Modular.get<ScrapedMetadataTransferService>(),
          ),
        ),
        onCompleted: Modular.get<CloudLibraryController>().load,
      ),
    );
    _child(
      r,
      "/cloud-sources/openlist/edit",
      child: (_) => OpenListSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
    _child(
      r,
      "/cloud-sources/quark/edit",
      child: (_) => QuarkSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
    _child(
      r,
      "/cloud-sources/baidu/edit",
      child: (_) => BaiduSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        credentialStore: Modular.get<CloudCredentialStore>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
    _child(
      r,
      "/cloud-sources/xunlei/edit",
      child: (_) => XunleiSourceEditorPage(
        controller: Modular.get<CloudLibraryController>(),
        credentialStore: Modular.get<CloudCredentialStore>(),
        onRootSelectionChanged:
            Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
        source: r.args.data is CloudSource ? r.args.data as CloudSource : null,
      ),
    );
    _child(
      r,
      "/cloud-sources/quark/import",
      child: (_) => r.args.data is CloudSource
          ? QuarkShareImportPage(
              source: r.args.data as CloudSource,
              cloudLibraryController: Modular.get<CloudLibraryController>(),
            )
          : const Scaffold(body: Center(child: Text('夸克来源不存在'))),
    );
    _child(
      r,
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
