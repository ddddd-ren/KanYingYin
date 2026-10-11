import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_user_data_store.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';

@immutable
final class ConfigurationMergeSummary {
  const ConfigurationMergeSummary({
    required this.added,
    required this.updated,
    required this.preserved,
    required this.tmdbWillUpdate,
    required this.requiresRootSelection,
    this.userStateCount = 0,
    this.bookmarkCount = 0,
    this.historyCount = 0,
    this.timelineCount = 0,
    this.watchStateCount = 0,
  });

  final int added;
  final int updated;
  final int preserved;
  final bool tmdbWillUpdate;
  final int requiresRootSelection;
  final int userStateCount;
  final int bookmarkCount;
  final int historyCount;
  final int timelineCount;
  final int watchStateCount;
}

typedef ConfigurationImportResult = ConfigurationMergeSummary;

abstract interface class ConfigurationImportPort {
  Future<ConfigurationMergeSummary> preview(
    PortableAppConfiguration configuration,
  );

  Future<ConfigurationImportResult> apply(
    PortableAppConfiguration configuration,
  );
}

final class ConfigurationImporter implements ConfigurationImportPort {
  ConfigurationImporter({
    required CloudSourceRepository sourceRepository,
    required TmdbCredentialManager tmdbCredentialManager,
    ConfigurationUserDataStore? userDataStore,
  })  : _sourceRepository = sourceRepository,
        _tmdbCredentialManager = tmdbCredentialManager,
        _userDataStore = userDataStore;

  final CloudSourceRepository _sourceRepository;
  final TmdbCredentialManager _tmdbCredentialManager;
  final ConfigurationUserDataStore? _userDataStore;

  @override
  Future<ConfigurationMergeSummary> preview(
    PortableAppConfiguration configuration,
  ) async {
    final current = await _sourceRepository.getAll();
    final currentIds = current.map((source) => source.id).toSet();
    final importedIds =
        configuration.cloudSources.map((record) => record.source.id).toSet();
    return ConfigurationMergeSummary(
      added: importedIds.difference(currentIds).length,
      updated: importedIds.intersection(currentIds).length,
      preserved: currentIds.difference(importedIds).length,
      tmdbWillUpdate: configuration.tmdbApiKey.isNotEmpty,
      userStateCount: configuration.userData?.states.length ?? 0,
      bookmarkCount: configuration.userData?.bookmarks.values
              .fold<int>(0, (count, list) => count + list.length) ??
          0,
      historyCount: configuration.userData?.history.length ?? 0,
      timelineCount: configuration.userData?.timelineSegments.length ?? 0,
      watchStateCount: configuration.userData?.watchStates.length ?? 0,
      requiresRootSelection: configuration.cloudSources
          .where((record) => record.requiresRootSelection)
          .length,
    );
  }

  @override
  Future<ConfigurationImportResult> apply(
    PortableAppConfiguration configuration,
  ) =>
      userDataMutationLock.synchronized(() async {
        final summary = await preview(configuration);
        final previousTmdb = _tmdbCredentialManager.exportForPairing();
        final shouldUpdateTmdb = configuration.tmdbApiKey.isNotEmpty;
        final userData = configuration.userData;
        if (userData != null && _userDataStore == null) {
          throw const ConfigurationImportException();
        }
        final previousUserData =
            userData == null ? null : await _userDataStore!.capture();
        var userDataTouched = false;
        var tmdbTouched = false;
        try {
          // 来源导入自带回滚，放在最后，避免后续用户数据失败留下新凭据。
          if (userData != null) {
            final merged = previousUserData!.merge(userData);
            userDataTouched = true;
            await _userDataStore!.replace(merged);
          }
          if (shouldUpdateTmdb) {
            tmdbTouched = true;
            await _tmdbCredentialManager.importForPairing(
              configuration.tmdbApiKey,
            );
          }
          await _sourceRepository.importForPairing(
            configuration.cloudSources
                .map(
                  (record) => CloudSourcePairingEntry(
                    source: record.source,
                    credential: record.credential,
                  ),
                )
                .toList(growable: false),
          );
          return summary;
        } on Object catch (error) {
          var rollbackFailed = error is CloudSourcePairingRollbackException;
          try {
            await _restoreUserData(previousUserData, userDataTouched);
          } on Object {
            rollbackFailed = true;
          }
          try {
            await _restoreTmdb(previousTmdb, tmdbTouched);
          } on Object {
            rollbackFailed = true;
          }
          if (rollbackFailed) throw const ConfigurationRollbackException();
          if (error is MediaLibraryClassificationConflict) rethrow;
          throw const ConfigurationImportException();
        }
      });

  Future<void> _restoreUserData(PortableUserData? data, bool touched) async {
    if (!touched) return;
    try {
      await _userDataStore!.replace(data!);
    } on Object {
      throw const ConfigurationRollbackException();
    }
  }

  Future<void> _restoreTmdb(String previousTmdb, bool touched) async {
    if (!touched) return;
    try {
      await _tmdbCredentialManager.importForPairing(previousTmdb);
    } on Object {
      throw const ConfigurationRollbackException();
    }
  }
}

final class ConfigurationImportException implements Exception {
  const ConfigurationImportException();

  @override
  String toString() => 'ConfigurationImportException';
}

final class ConfigurationRollbackException implements Exception {
  const ConfigurationRollbackException();

  @override
  String toString() => 'ConfigurationRollbackException';
}
