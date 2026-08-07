import 'dart:io';

import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';

abstract interface class TvPreloadConfigurationPort {
  Future<ConfigurationMergeSummary> importEncrypted(
    File file, {
    required String password,
  });
}

abstract interface class TvPreloadMetadataPort {
  Future<ScrapedMetadataTransferResult> importArchive(File file);
}

abstract interface class TvPreloadMediaRefreshPort {
  Future<TvPreloadMediaRefreshResult> loadAndScanEnabledSources();
}

abstract interface class TvPreloadStatePort {
  String? readManifestHash();

  Future<void> writeSuccess({
    required String manifestHash,
    required TvPreloadImportResult result,
  });

  Future<void> writeFailure(String errorCode);
}

final class TvPreloadMediaRefreshResult {
  const TvPreloadMediaRefreshResult({
    required this.scanned,
    required this.failed,
  });

  final int scanned;
  final int failed;
}

enum TvPreloadImportStatus { skipped, success, partial, failed }

final class TvPreloadImportResult {
  const TvPreloadImportResult({
    required this.status,
    this.configurationSummary,
    this.metadataResult,
    this.mediaRefreshResult,
    this.errorCode,
  });

  final TvPreloadImportStatus status;
  final ConfigurationMergeSummary? configurationSummary;
  final ScrapedMetadataTransferResult? metadataResult;
  final TvPreloadMediaRefreshResult? mediaRefreshResult;
  final String? errorCode;
}

final class ConfigurationTransferPreloadAdapter
    implements TvPreloadConfigurationPort {
  const ConfigurationTransferPreloadAdapter(this.service);

  final ConfigurationTransferService service;

  @override
  Future<ConfigurationMergeSummary> importEncrypted(
    File file, {
    required String password,
  }) async {
    final session = await service.inspect(
      await file.readAsBytes(),
      password: password,
    );
    return service.apply(session);
  }
}

final class ScrapedMetadataTransferPreloadAdapter
    implements TvPreloadMetadataPort {
  const ScrapedMetadataTransferPreloadAdapter(this.service);

  final ScrapedMetadataTransferService service;

  @override
  Future<ScrapedMetadataTransferResult> importArchive(File file) async {
    final session = await service.inspect(file);
    return service.apply(session);
  }
}

final class CloudLibraryPreloadRefreshAdapter
    implements TvPreloadMediaRefreshPort {
  const CloudLibraryPreloadRefreshAdapter(this.controller);

  final CloudLibraryController controller;

  @override
  Future<TvPreloadMediaRefreshResult> loadAndScanEnabledSources() async {
    final loaded = await controller.load();
    if (!loaded) {
      return const TvPreloadMediaRefreshResult(scanned: 0, failed: 1);
    }
    var scanned = 0;
    var failed = 0;
    for (final source in controller.sources) {
      if (!source.enabled || source.remoteRoots.isEmpty) continue;
      try {
        await controller.scanSource(source.id);
        scanned++;
      } on Object {
        failed++;
      }
    }
    return TvPreloadMediaRefreshResult(scanned: scanned, failed: failed);
  }
}

final class HiveTvPreloadStateAdapter implements TvPreloadStatePort {
  const HiveTvPreloadStateAdapter(this.settings);

  final TypedSettings settings;

  @override
  String? readManifestHash() => settings.getTyped<String?>(
        SettingBoxKey.tvPreloadManifestHash,
        defaultValue: null,
      );

  @override
  Future<void> writeSuccess({
    required String manifestHash,
    required TvPreloadImportResult result,
  }) async {
    await settings.put(SettingBoxKey.tvPreloadManifestHash, manifestHash);
    await settings.put(
      SettingBoxKey.tvPreloadLastResult,
      result.status.name,
    );
    await settings.delete(SettingBoxKey.tvPreloadLastError);
  }

  @override
  Future<void> writeFailure(String errorCode) async {
    await settings.put(SettingBoxKey.tvPreloadLastResult, 'failed');
    await settings.put(SettingBoxKey.tvPreloadLastError, errorCode);
  }
}
