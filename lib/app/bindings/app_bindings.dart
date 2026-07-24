import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/app/bindings/cloud_bindings.dart';
import 'package:kanyingyin/app/bindings/infrastructure_bindings.dart';
import 'package:kanyingyin/app/bindings/library_bindings.dart';
import 'package:kanyingyin/app/bindings/playback_bindings.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

/// 以原有单例作用域注册全部应用依赖。
void registerApplicationBindings(
  Injector i, {
  required TmdbCredentialManager tmdbCredentialManager,
}) {
  registerInfrastructureBindings(
    i,
    tmdbCredentialManager: tmdbCredentialManager,
  );
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
}
