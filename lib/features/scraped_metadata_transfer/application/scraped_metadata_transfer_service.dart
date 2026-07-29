import 'dart:io';

import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';

typedef ScrapedMetadataExportBuilder = Future<ScrapedMetadataExportDraft>
    Function();
typedef ScrapedMetadataArchiveWriter = Future<File> Function({
  required File output,
  required ScrapedMetadataPayload payload,
  required Map<String, File> images,
});
typedef ScrapedMetadataArchiveReader = Future<DecodedScrapedMetadataArchive>
    Function(File input);
typedef ScrapedMetadataPlanBuilder = Future<ScrapedMetadataImportPlan> Function(
  ScrapedMetadataPayload payload,
  Map<String, String> localOverrides,
);
typedef ScrapedMetadataPlanImporter = Future<ScrapedMetadataTransferResult>
    Function(
  ScrapedMetadataImportPlan plan,
  DecodedScrapedMetadataArchive archive,
);

final class ScrapedMetadataImportSession {
  ScrapedMetadataImportSession({
    required this.archive,
    required this.plan,
  });

  final DecodedScrapedMetadataArchive archive;
  ScrapedMetadataImportPlan plan;
  final Map<String, String> localOverrides = <String, String>{};
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await archive.dispose();
  }
}

final class ScrapedMetadataTransferService {
  ScrapedMetadataTransferService({
    required ScrapedMetadataExportBuilder buildExport,
    required ScrapedMetadataArchiveWriter writeArchive,
    required ScrapedMetadataArchiveReader readArchive,
    required ScrapedMetadataPlanBuilder buildPlan,
    required ScrapedMetadataPlanImporter importPlan,
  })  : _buildExport = buildExport,
        _writeArchive = writeArchive,
        _readArchive = readArchive,
        _buildPlan = buildPlan,
        _importPlan = importPlan;

  final ScrapedMetadataExportBuilder _buildExport;
  final ScrapedMetadataArchiveWriter _writeArchive;
  final ScrapedMetadataArchiveReader _readArchive;
  final ScrapedMetadataPlanBuilder _buildPlan;
  final ScrapedMetadataPlanImporter _importPlan;

  Future<ScrapedMetadataTransferResult> exportTo(File output) async {
    final draft = await _buildExport();
    await _writeArchive(
      output: output,
      payload: draft.payload,
      images: draft.images,
    );
    return ScrapedMetadataTransferResult(
      localCount: draft.payload.localSources.fold<int>(
        0,
        (sum, source) => sum + source.records.length,
      ),
      cloudCount: draft.payload.cloudSources.fold<int>(
        0,
        (sum, source) => sum + source.recordCount,
      ),
      imageCount: draft.images.length,
      skippedCount: draft.skippedCount,
    );
  }

  Future<ScrapedMetadataImportSession> inspect(File input) async {
    final archive = await _readArchive(input);
    try {
      final plan = await _buildPlan(
        archive.payload,
        const <String, String>{},
      );
      return ScrapedMetadataImportSession(archive: archive, plan: plan);
    } on Object {
      await archive.dispose();
      rethrow;
    }
  }

  Future<void> remapLocal(
    ScrapedMetadataImportSession session,
    String exportSourceId,
    String targetRoot,
  ) async {
    session.localOverrides[exportSourceId] = targetRoot;
    session.plan = await _buildPlan(
      session.archive.payload,
      Map<String, String>.unmodifiable(session.localOverrides),
    );
  }

  Future<ScrapedMetadataTransferResult> apply(
    ScrapedMetadataImportSession session,
  ) async {
    try {
      return await _importPlan(session.plan, session.archive);
    } finally {
      await session.dispose();
    }
  }
}
