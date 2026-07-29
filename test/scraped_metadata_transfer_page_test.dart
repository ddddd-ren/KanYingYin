import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/presentation/scraped_metadata_transfer_page.dart';

void main() {
  testWidgets(
    '迁移页提供导出和导入入口并在确认后才写入',
    (tester) async {
      final archiveDirectory =
          Directory.systemTemp.createTempSync('kyymeta-page-test-');
      addTearDown(() {
        if (archiveDirectory.existsSync()) {
          archiveDirectory.deleteSync(recursive: true);
        }
      });
      final archive = DecodedScrapedMetadataArchive(
        payload: _payload(),
        imageFiles: const <String, File>{},
        temporaryDirectory: archiveDirectory,
      );
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
        buildPlan: (_, __) async => _plan(archive.payload),
        importPlan: (_, __) async {
          applyCount++;
          return const ScrapedMetadataTransferResult(
            localCount: 1,
            cloudCount: 0,
            imageCount: 0,
            skippedCount: 2,
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ScrapedMetadataTransferPage(
            service: service,
            saveFilePicker: () async => null,
            openFilePicker: () async => 'test.kyymeta',
            localDirectoryPicker: (_, __) async => null,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('刮削资料迁移'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('export-scraped-metadata')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('import-scraped-metadata')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('import-scraped-metadata')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('将覆盖 0 项'), findsOneWidget);
      expect(find.textContaining('未找到 2 项'), findsOneWidget);
      expect(applyCount, 0);

      await tester.tap(find.text('确认导入'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 50; attempt++) {
          if (!archiveDirectory.existsSync()) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(applyCount, 1);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
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
      missingMediaCount: 2,
      recoverableImageCount: 0,
    );
