import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';

void main() {
  test('导出组合资料和归档并返回准确统计', () async {
    final temporary =
        await Directory.systemTemp.createTemp('kyymeta-service-export-');
    addTearDown(() => temporary.delete(recursive: true));
    final output = File(
      '${temporary.path}${Platform.pathSeparator}资料.kyymeta',
    );
    var writerCalled = false;
    final service = ScrapedMetadataTransferService(
      buildExport: () async => ScrapedMetadataExportDraft(
        payload: _payload(),
        images: const <String, File>{},
        skippedCount: 2,
      ),
      writeArchive: ({
        required File output,
        required ScrapedMetadataPayload payload,
        required Map<String, File> images,
      }) async {
        writerCalled = true;
        await output.writeAsString('archive');
        return output;
      },
      readArchive: (_) => throw UnimplementedError(),
      buildPlan: (_, __) => throw UnimplementedError(),
      importPlan: (_, __) => throw UnimplementedError(),
    );

    final result = await service.exportTo(output);

    expect(writerCalled, isTrue);
    expect(result.localCount, 1);
    expect(result.cloudCount, 0);
    expect(result.skippedCount, 2);
    expect(await output.exists(), isTrue);
  });

  test('确认导入后应用计划并清理临时解包目录', () async {
    final archiveDirectory =
        await Directory.systemTemp.createTemp('kyymeta-service-import-');
    final input = File('${archiveDirectory.parent.path}\\input.kyymeta');
    final archive = DecodedScrapedMetadataArchive(
      payload: _payload(),
      imageFiles: const <String, File>{},
      temporaryDirectory: archiveDirectory,
    );
    final plan = _plan(archive.payload);
    var applyCount = 0;
    final service = ScrapedMetadataTransferService(
      buildExport: () => throw UnimplementedError(),
      writeArchive: ({
        required File output,
        required ScrapedMetadataPayload payload,
        required Map<String, File> images,
      }) =>
          throw UnimplementedError(),
      readArchive: (_) async => archive,
      buildPlan: (_, __) async => plan,
      importPlan: (_, __) async {
        applyCount++;
        return const ScrapedMetadataTransferResult(
          localCount: 1,
          cloudCount: 0,
          imageCount: 0,
          skippedCount: 0,
        );
      },
    );

    final session = await service.inspect(input);
    final result = await service.apply(session);

    expect(result.localCount, 1);
    expect(applyCount, 1);
    expect(await archiveDirectory.exists(), isFalse);
  });

  test('取消导入也会清理临时解包目录', () async {
    final archiveDirectory =
        await Directory.systemTemp.createTemp('kyymeta-service-cancel-');
    final archive = DecodedScrapedMetadataArchive(
      payload: _payload(),
      imageFiles: const <String, File>{},
      temporaryDirectory: archiveDirectory,
    );
    final service = ScrapedMetadataTransferService(
      buildExport: () => throw UnimplementedError(),
      writeArchive: ({
        required File output,
        required ScrapedMetadataPayload payload,
        required Map<String, File> images,
      }) =>
          throw UnimplementedError(),
      readArchive: (_) async => archive,
      buildPlan: (_, __) async => _plan(archive.payload),
      importPlan: (_, __) => throw UnimplementedError(),
    );

    final session = await service.inspect(File('unused.kyymeta'));
    await session.dispose();

    expect(await archiveDirectory.exists(), isFalse);
  });
}

ScrapedMetadataPayload _payload() => ScrapedMetadataPayload(
      formatVersion: scrapedMetadataFormatVersion,
      exportedAt: DateTime.utc(2026, 7, 30),
      appVersion: '2.1.93',
      localSources: <PortableLocalSource>[
        PortableLocalSource(
          exportId: 'local',
          name: '影视',
          originalRoot: r'D:\影视',
          records: <PortableLocalRecord>[
            PortableLocalRecord(
              relativePath: '三体.mkv',
              size: 1,
              tmdb: <String, Object?>{'id': 42, 'title': '三体'},
              scrapeStatus: 'matched',
              tmdbMatchOrigin: 'manual',
              tmdbRuleVersion: 1,
            ),
          ],
        ),
      ],
      cloudSources: const <PortableCloudSource>[],
    );

ScrapedMetadataImportPlan _plan(ScrapedMetadataPayload payload) =>
    ScrapedMetadataImportPlan(
      payload: payload,
      localMappings: const <String, String>{},
      cloudMappings: const <String, String>{},
      localMatches: const <LocalImportMatch>[],
      cloudResourceMatches: const <CloudResourceImportMatch>[],
      cloudWorkMatches: const <CloudWorkImportMatch>[],
      cloudSeriesRuleMatches: const <CloudSeriesRuleImportMatch>[],
      unresolvedLocalSources: const <PortableLocalSource>[],
      unresolvedCloudSources: const <PortableCloudSource>[],
      missingMediaCount: 0,
      recoverableImageCount: 0,
    );
