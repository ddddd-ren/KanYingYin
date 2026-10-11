import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_user_data_store.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

@immutable
final class ConfigurationImportSession {
  const ConfigurationImportSession({
    required this.configuration,
    required this.summary,
  });

  final PortableAppConfiguration configuration;
  final ConfigurationMergeSummary summary;
}

final class ConfigurationTransferService {
  ConfigurationTransferService({
    required CloudSourceRepository sourceRepository,
    required TmdbCredentialManager tmdbCredentialManager,
    required ConfigurationImportPort importer,
    required ConfigurationArchiveCodec codec,
    ConfigurationUserDataStore? userDataStore,
    Future<void> Function()? flushUserData,
    DateTime Function()? now,
    String? appVersion,
  })  : _sourceRepository = sourceRepository,
        _tmdbCredentialManager = tmdbCredentialManager,
        _importer = importer,
        _codec = codec,
        _userDataStore = userDataStore,
        _flushUserData = flushUserData,
        now = now ?? DateTime.now,
        appVersion = appVersion ?? AppVersion.current;

  final CloudSourceRepository _sourceRepository;
  final TmdbCredentialManager _tmdbCredentialManager;
  final ConfigurationImportPort _importer;
  final ConfigurationArchiveCodec _codec;
  final ConfigurationUserDataStore? _userDataStore;
  final Future<void> Function()? _flushUserData;
  final DateTime Function() now;
  final String appVersion;

  Future<PortableAppConfiguration> capture() async {
    await _flushUserData?.call();
    final entries = await _sourceRepository.exportForPairing();
    return PortableAppConfiguration.create(
      exportedAt: now().toUtc(),
      appVersion: appVersion,
      tmdbApiKey: _tmdbCredentialManager.exportForPairing(),
      userData: await _userDataStore?.capture(),
      cloudSources: entries
          .map(
            (entry) => PortableCloudSourceConfiguration.fromSource(
              source: entry.source,
              credential: entry.credential,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<Uint8List> exportEncrypted({required String password}) async {
    final configuration = await capture();
    return encrypt(configuration, password: password);
  }

  Future<Uint8List> encrypt(
    PortableAppConfiguration configuration, {
    required String password,
  }) =>
      _codec.encrypt(configuration, password: password);

  Future<ConfigurationImportSession> inspect(
    Uint8List bytes, {
    required String password,
  }) async {
    final configuration = await _codec.decrypt(bytes, password: password);
    return ConfigurationImportSession(
      configuration: configuration,
      summary: await _importer.preview(configuration),
    );
  }

  Future<ConfigurationImportResult> apply(
    ConfigurationImportSession session,
  ) =>
      _importer.apply(session.configuration);

  Future<List<CloudSource>> availableSources() => _sourceRepository.getAll();

  Future<ConfigurationImportSession> remapSession(
    ConfigurationImportSession session, {
    Map<String, String> localRoots = const {},
    Map<String, String> cloudSources = const {},
  }) async {
    final current = {
      for (final source in await availableSources()) source.id: source
    };
    final config = session.configuration;
    final records = config.cloudSources.map((record) {
      final targetId = cloudSources[record.source.id];
      if (targetId == null || targetId == record.source.id) return record;
      final target = current[targetId];
      if (target == null ||
          target.type != record.source.type ||
          target.baseUrl != record.source.baseUrl) {
        throw const PortableConfigurationValidationException(
            'invalid_source_mapping');
      }
      return PortableCloudSourceConfiguration.fromSource(
        source: target,
        credential: record.credential,
      );
    }).toList();
    final mapped = PortableAppConfiguration.create(
      exportedAt: config.exportedAt,
      appVersion: config.appVersion,
      tmdbApiKey: config.tmdbApiKey,
      cloudSources: records,
      userData: config.userData
          ?.remap(localRoots: localRoots, cloudSources: cloudSources),
    );
    return ConfigurationImportSession(
        configuration: mapped, summary: await _importer.preview(mapped));
  }
}
