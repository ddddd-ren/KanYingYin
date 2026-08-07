import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv_preload/data/tv_preload_asset_reader.dart';
import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';

void main() {
  test('禁用清单不启用个人预置导入', () {
    final manifest = TvPreloadManifest.fromJson(const <String, Object?>{
      'enabled': false,
      'version': 1,
    });

    expect(manifest.enabled, isFalse);
    expect(manifest.version, 1);
    expect(manifest.toString(), isNot(contains('password')));
  });

  test('启用清单保留资源元数据并拒绝不安全路径', () {
    final manifest = TvPreloadManifest.fromJson(const <String, Object?>{
      'enabled': true,
      'version': 1,
      'configurationAsset': 'assets/tv_preload/configuration.kyyconfig',
      'metadataAsset': 'assets/tv_preload/metadata.kyymeta',
      'configurationBytes': 12,
      'metadataBytes': 34,
      'configurationSha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'metadataSha256':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    });

    expect(manifest.configurationBytes, 12);
    expect(manifest.metadataBytes, 34);
    expect(manifest.configurationAsset, endsWith('.kyyconfig'));
    expect(manifest.metadataAsset, endsWith('.kyymeta'));

    expect(
      () => TvPreloadManifest.fromJson(const <String, Object?>{
        'enabled': true,
        'version': 1,
        'configurationAsset': '../configuration.kyyconfig',
        'metadataAsset': 'assets/tv_preload/metadata.kyymeta',
        'configurationBytes': 1,
        'metadataBytes': 1,
        'configurationSha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'metadataSha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      }),
      throwsA(isA<TvPreloadManifestException>()),
    );
  });

  test('资源读取器校验大小和 SHA-256 后写入临时文件', () async {
    final temporary = await Directory.systemTemp.createTemp('tv-preload-');
    addTearDown(() => temporary.delete(recursive: true));
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final reader = TvPreloadAssetReader(
      loadAsset: (_) async => bytes,
      temporaryDirectory: () async => temporary,
    );

    final file = await reader.copyVerifiedAsset(
      assetPath: 'assets/tv_preload/metadata.kyymeta',
      expectedBytes: 4,
      expectedSha256: sha256.convert(bytes).toString(),
      fileName: 'metadata.kyymeta',
    );

    expect(await file.readAsBytes(), bytes);
    expect(file.path, endsWith('metadata.kyymeta'));
  });

  test('资源读取器在哈希不匹配时不保留半成品', () async {
    final temporary = await Directory.systemTemp.createTemp('tv-preload-');
    addTearDown(() => temporary.delete(recursive: true));
    final reader = TvPreloadAssetReader(
      loadAsset: (_) async => Uint8List.fromList(<int>[9, 8, 7]),
      temporaryDirectory: () async => temporary,
    );

    await expectLater(
      reader.copyVerifiedAsset(
        assetPath: 'assets/tv_preload/configuration.kyyconfig',
        expectedBytes: 3,
        expectedSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        fileName: 'configuration.kyyconfig',
      ),
      throwsA(isA<TvPreloadAssetException>()),
    );
    expect(temporary.listSync(), isEmpty);
  });
}
