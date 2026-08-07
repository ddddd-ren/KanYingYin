import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:synchronized/synchronized.dart';

@immutable
final class ConfigurationMergeSummary {
  const ConfigurationMergeSummary({
    required this.added,
    required this.updated,
    required this.preserved,
    required this.tmdbWillUpdate,
    required this.requiresRootSelection,
  });

  final int added;
  final int updated;
  final int preserved;
  final bool tmdbWillUpdate;
  final int requiresRootSelection;
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
  })  : _sourceRepository = sourceRepository,
        _tmdbCredentialManager = tmdbCredentialManager;

  final CloudSourceRepository _sourceRepository;
  final TmdbCredentialManager _tmdbCredentialManager;
  final Lock _mutationLock = Lock();

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
      requiresRootSelection: configuration.cloudSources
          .where((record) => record.requiresRootSelection)
          .length,
    );
  }

  @override
  Future<ConfigurationImportResult> apply(
    PortableAppConfiguration configuration,
  ) =>
      _mutationLock.synchronized(() async {
        final summary = await preview(configuration);
        final previousTmdb = _tmdbCredentialManager.exportForPairing();
        final shouldUpdateTmdb = configuration.tmdbApiKey.isNotEmpty;
        try {
          if (shouldUpdateTmdb) {
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
        } on CloudSourcePairingRollbackException {
          await _restoreTmdb(previousTmdb, shouldUpdateTmdb);
          throw const ConfigurationRollbackException();
        } on Object {
          await _restoreTmdb(previousTmdb, shouldUpdateTmdb);
          throw const ConfigurationImportException();
        }
      });

  Future<void> _restoreTmdb(String previousTmdb, bool shouldUpdateTmdb) async {
    if (!shouldUpdateTmdb) return;
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
