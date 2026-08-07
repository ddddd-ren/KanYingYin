import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/app/bindings/cloud_bindings.dart';
import 'package:kanyingyin/app/bindings/infrastructure_bindings.dart';
import 'package:kanyingyin/app/bindings/history_bindings.dart';
import 'package:kanyingyin/app/bindings/library_bindings.dart';
import 'package:kanyingyin/app/bindings/playback_bindings.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_ports.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_service.dart';
import 'package:kanyingyin/features/tv_preload/data/tv_preload_asset_reader.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

/// 以原有单例作用域注册全部应用依赖。
void registerApplicationBindings(
  Injector i, {
  required TmdbCredentialManager tmdbCredentialManager,
}) {
  registerInfrastructureBindings(
    i,
    tmdbCredentialManager: tmdbCredentialManager,
  );
  registerHistoryBindings(i);
  registerCloudBindings(i);
  registerLibraryBindings(i);
  registerPlaybackBindings(i);
  _registerCrossFeatureBindings(i);
}

void _registerCrossFeatureBindings(Injector i) {
  i.addSingleton<CloudSourceRootRefreshCoordinator>(
    () => CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () =>
          Modular.get<LocalController>().reloadCloudLibraryIndex(
        throwOnFailure: true,
      ),
      reloadCloudResources: () =>
          Modular.get<CloudResourcesController>().reloadSourcesAndSnapshot(),
      scanSource: (sourceId) =>
          Modular.get<CloudLibraryController>().scanSource(sourceId),
    ),
  );
  i.addSingleton<TvPreloadImportService>(
    () => TvPreloadImportService(
      capabilities: detectAppPlatform(),
      assets: TvPreloadAssetReader(),
      configuration: ConfigurationTransferPreloadAdapter(
        Modular.get<ConfigurationTransferService>(),
      ),
      metadata: ScrapedMetadataTransferPreloadAdapter(
        Modular.get<ScrapedMetadataTransferService>(),
      ),
      media: CloudLibraryPreloadRefreshAdapter(
        Modular.get<CloudLibraryController>(),
      ),
      state: HiveTvPreloadStateAdapter(Modular.get<TypedSettings>()),
    ),
  );
}
