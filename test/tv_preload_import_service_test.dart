import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_ports.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_service.dart';
import 'package:kanyingyin/features/tv_preload/data/tv_preload_asset_reader.dart';
import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('预置导入按配置、刷新网盘、刮削资料的顺序执行并写入标记', () async {
    final temporary = await Directory.systemTemp.createTemp('tv-preload-');
    addTearDown(() => temporary.delete(recursive: true));
    final events = <String>[];
    final state = _FakePreloadState();
    final manifest = _enabledManifest();
    final service = _createService(
      events: events,
      state: state,
      manifest: manifest,
      temporary: temporary,
    );

    final result = await service.run();

    expect(result.status, TvPreloadImportStatus.success);
    expect(events, <String>[
      'read-manifest',
      'copy:configuration.kyyconfig',
      'configuration',
      'load-and-scan',
      'copy:metadata.kyymeta',
      'metadata',
    ]);
    expect(
      state.manifestHash,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
  });

  test('配置导入失败时不刷新媒体源、不导入资料且不写成功标记', () async {
    final temporary = await Directory.systemTemp.createTemp('tv-preload-');
    addTearDown(() => temporary.delete(recursive: true));
    final events = <String>[];
    final service = _createService(
      events: events,
      state: _FakePreloadState(),
      manifest: _enabledManifest(),
      temporary: temporary,
      configurationError: StateError('配置导入失败'),
    );

    final result = await service.run();

    expect(result.status, TvPreloadImportStatus.failed);
    expect(events, <String>[
      'read-manifest',
      'copy:configuration.kyyconfig',
      'configuration',
    ]);
  });

  test('已有相同清单哈希时跳过重复导入', () async {
    final state = _FakePreloadState()
      ..manifestHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:'
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final events = <String>[];
    final temporary = await Directory.systemTemp.createTemp('tv-preload-');
    addTearDown(() => temporary.delete(recursive: true));
    final service = _createService(
      events: events,
      state: state,
      manifest: _enabledManifest(),
      temporary: temporary,
    );

    final result = await service.run();

    expect(result.status, TvPreloadImportStatus.skipped);
    expect(events, <String>['read-manifest']);
  });

  test('资料存在未匹配项时返回部分成功并保存结果', () async {
    final state = _FakePreloadState();
    final events = <String>[];
    final temporary = await Directory.systemTemp.createTemp('tv-preload-');
    addTearDown(() => temporary.delete(recursive: true));
    final service = _createService(
      events: events,
      state: state,
      manifest: _enabledManifest(),
      temporary: temporary,
      metadataResult: const ScrapedMetadataTransferResult(
        localCount: 2,
        cloudCount: 1,
        imageCount: 3,
        skippedCount: 4,
      ),
    );

    final result = await service.run();

    expect(result.status, TvPreloadImportStatus.partial);
    expect(result.metadataResult?.skippedCount, 4);
    expect(
      state.manifestHash,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
  });
}

TvPreloadImportService _createService({
  required List<String> events,
  required _FakePreloadState state,
  required TvPreloadManifest manifest,
  required Directory temporary,
  Object? configurationError,
  ScrapedMetadataTransferResult? metadataResult,
}) {
  return TvPreloadImportService(
    capabilities: AppPlatformCapabilities.android.copyWith(television: true),
    password: 'test-password',
    assets: _FakePreloadAssets(events, manifest, temporary),
    configuration: _FakeConfigurationPort(events, configurationError),
    metadata: _FakeMetadataPort(
      events,
      metadataResult ??
          const ScrapedMetadataTransferResult(
            localCount: 1,
            cloudCount: 1,
            imageCount: 1,
            skippedCount: 0,
          ),
    ),
    media: _FakeMediaPort(events),
    state: state,
  );
}

TvPreloadManifest _enabledManifest() => const TvPreloadManifest(
      enabled: true,
      version: TvPreloadManifest.currentVersion,
      configurationAsset: 'assets/tv_preload/configuration.kyyconfig',
      metadataAsset: 'assets/tv_preload/metadata.kyymeta',
      configurationBytes: 3,
      metadataBytes: 3,
      configurationSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      metadataSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

class _FakePreloadAssets implements TvPreloadAssetPort {
  _FakePreloadAssets(this.events, this.manifest, this.temporary);

  final List<String> events;
  final TvPreloadManifest manifest;
  final Directory temporary;

  @override
  Future<TvPreloadManifest> readManifest() async {
    events.add('read-manifest');
    return manifest;
  }

  @override
  Future<File> copyVerifiedAsset({
    required String assetPath,
    required int expectedBytes,
    required String expectedSha256,
    required String fileName,
  }) async {
    events.add('copy:$fileName');
    final file = File('${temporary.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(const <int>[1, 2, 3]);
    return file;
  }
}

class _FakeConfigurationPort implements TvPreloadConfigurationPort {
  _FakeConfigurationPort(this.events, this.error);

  final List<String> events;
  final Object? error;

  @override
  Future<ConfigurationMergeSummary> importEncrypted(
    File file, {
    required String password,
  }) async {
    events.add('configuration');
    if (error != null) throw error!;
    return const ConfigurationMergeSummary(
      added: 1,
      updated: 0,
      preserved: 0,
      tmdbWillUpdate: true,
      requiresRootSelection: 0,
    );
  }
}

class _FakeMetadataPort implements TvPreloadMetadataPort {
  _FakeMetadataPort(this.events, this.result);

  final List<String> events;
  final ScrapedMetadataTransferResult result;

  @override
  Future<ScrapedMetadataTransferResult> importArchive(File file) async {
    events.add('metadata');
    return result;
  }
}

class _FakeMediaPort implements TvPreloadMediaRefreshPort {
  _FakeMediaPort(this.events);

  final List<String> events;

  @override
  Future<TvPreloadMediaRefreshResult> loadAndScanEnabledSources() async {
    events.add('load-and-scan');
    return const TvPreloadMediaRefreshResult(scanned: 1, failed: 0);
  }
}

class _FakePreloadState implements TvPreloadStatePort {
  String? manifestHash;

  @override
  String? readManifestHash() => manifestHash;

  @override
  Future<void> writeFailure(String errorCode) async {}

  @override
  Future<void> writeSuccess({
    required String manifestHash,
    required TvPreloadImportResult result,
  }) async {
    this.manifestHash = manifestHash;
  }
}
