import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';

@immutable
final class TvPairingFileImportPreview {
  const TvPairingFileImportPreview({
    this.configurationSummary,
    this.hasConfigurationFile = false,
    this.hasScrapedMetadataFile = false,
    this.metadataMatchedCount = 0,
    this.metadataMissingMediaCount = 0,
    this.metadataRecoverableImageCount = 0,
  });

  final ConfigurationMergeSummary? configurationSummary;
  final bool hasConfigurationFile;
  final bool hasScrapedMetadataFile;
  final int metadataMatchedCount;
  final int metadataMissingMediaCount;
  final int metadataRecoverableImageCount;
}

@immutable
final class TvPairingFileImportResult {
  const TvPairingFileImportResult({
    this.configurationSummary,
    this.metadataResult,
  });

  final ConfigurationImportResult? configurationSummary;
  final ScrapedMetadataTransferResult? metadataResult;
}

abstract interface class TvPairingFileImportPort {
  Future<TvPairingFileImportPreview> preview(TvPairingPayload payload);

  Future<TvPairingFileImportResult> apply(TvPairingPayload payload);
}

final class TvPairingFileImportCoordinator implements TvPairingFileImportPort {
  TvPairingFileImportCoordinator({
    required ConfigurationTransferService configurationTransfer,
    required ScrapedMetadataTransferService metadataTransfer,
  })  : _configurationTransfer = configurationTransfer,
        _metadataTransfer = metadataTransfer;

  final ConfigurationTransferService _configurationTransfer;
  final ScrapedMetadataTransferService _metadataTransfer;

  @override
  Future<TvPairingFileImportPreview> preview(TvPairingPayload payload) async {
    final configurationFile =
        _fileFor(payload, TvPairingFileKind.configuration);
    final metadataFile = _fileFor(payload, TvPairingFileKind.scrapedMetadata);
    ConfigurationMergeSummary? configurationSummary;
    if (configurationFile != null) {
      final session = await _configurationTransfer.inspect(
        await _readConfiguration(configurationFile),
        password: payload.configurationFilePassword!.trim(),
      );
      configurationSummary = session.summary;
    }

    var metadataMatchedCount = 0;
    var metadataMissingMediaCount = 0;
    var metadataRecoverableImageCount = 0;
    if (metadataFile != null) {
      final session = await _metadataTransfer.inspect(File(metadataFile.path));
      try {
        metadataMatchedCount = session.plan.matchedCount;
        metadataMissingMediaCount = session.plan.missingMediaCount;
        metadataRecoverableImageCount = session.plan.recoverableImageCount;
      } finally {
        await session.dispose();
      }
    }
    return TvPairingFileImportPreview(
      configurationSummary: configurationSummary,
      hasConfigurationFile: configurationFile != null,
      hasScrapedMetadataFile: metadataFile != null,
      metadataMatchedCount: metadataMatchedCount,
      metadataMissingMediaCount: metadataMissingMediaCount,
      metadataRecoverableImageCount: metadataRecoverableImageCount,
    );
  }

  @override
  Future<TvPairingFileImportResult> apply(TvPairingPayload payload) async {
    final configurationFile =
        _fileFor(payload, TvPairingFileKind.configuration);
    final metadataFile = _fileFor(payload, TvPairingFileKind.scrapedMetadata);
    ConfigurationImportResult? configurationSummary;
    if (configurationFile != null) {
      final session = await _configurationTransfer.inspect(
        await _readConfiguration(configurationFile),
        password: payload.configurationFilePassword!.trim(),
      );
      configurationSummary = await _configurationTransfer.apply(session);
    }

    ScrapedMetadataTransferResult? metadataResult;
    if (metadataFile != null) {
      final session = await _metadataTransfer.inspect(File(metadataFile.path));
      metadataResult = await _metadataTransfer.apply(session);
    }
    return TvPairingFileImportResult(
      configurationSummary: configurationSummary,
      metadataResult: metadataResult,
    );
  }

  Future<Uint8List> _readConfiguration(TvPairingUploadedFile file) async {
    final bytes = await File(file.path).readAsBytes();
    return Uint8List.fromList(bytes);
  }

  TvPairingUploadedFile? _fileFor(
    TvPairingPayload payload,
    TvPairingFileKind kind,
  ) {
    final fileId = payload.fileIds[kind];
    if (fileId == null) return null;
    final file = payload.uploadedFiles[kind];
    if (file == null || file.id != fileId || file.kind != kind) {
      throw const TvPairingFileImportException('配对文件不存在或已失效');
    }
    return file;
  }
}

final class TvPairingFileImportException implements Exception {
  const TvPairingFileImportException(this.message);

  final String message;

  @override
  String toString() => 'TvPairingFileImportException($message)';
}
