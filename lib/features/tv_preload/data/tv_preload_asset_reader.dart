import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';

typedef TvPreloadAssetLoader = Future<Uint8List> Function(String assetPath);
typedef TvPreloadTemporaryDirectory = Future<Directory> Function();

abstract interface class TvPreloadAssetPort {
  Future<TvPreloadManifest> readManifest();

  Future<File> copyVerifiedAsset({
    required String assetPath,
    required int expectedBytes,
    required String expectedSha256,
    required String fileName,
  });
}

final class TvPreloadAssetReader implements TvPreloadAssetPort {
  TvPreloadAssetReader({
    TvPreloadAssetLoader? loadAsset,
    TvPreloadTemporaryDirectory? temporaryDirectory,
  })  : _loadAsset = loadAsset ?? _loadBundleAsset,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final TvPreloadAssetLoader _loadAsset;
  final TvPreloadTemporaryDirectory _temporaryDirectory;

  @override
  Future<TvPreloadManifest> readManifest() async {
    try {
      return TvPreloadManifest.fromBytes(
        await _loadAsset(tvPreloadManifestAsset),
      );
    } on TvPreloadManifestException {
      rethrow;
    } on Object {
      throw const TvPreloadAssetException('预置清单读取失败');
    }
  }

  @override
  Future<File> copyVerifiedAsset({
    required String assetPath,
    required int expectedBytes,
    required String expectedSha256,
    required String fileName,
  }) async {
    _validateAssetPath(assetPath);
    final bytes = await _loadAsset(assetPath);
    if (bytes.length != expectedBytes ||
        sha256.convert(bytes).toString() != expectedSha256) {
      throw const TvPreloadAssetException('预置资源校验失败');
    }
    final directory = await _temporaryDirectory();
    final output = File(p.join(directory.path, 'tv-preload-$fileName'));
    try {
      await output.writeAsBytes(bytes, flush: true);
      return output;
    } on Object {
      try {
        if (await output.exists()) await output.delete();
      } on Object {
        // 临时文件清理失败不覆盖原始错误。
      }
      rethrow;
    }
  }

  static Future<Uint8List> _loadBundleAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  static void _validateAssetPath(String value) {
    if (!value.startsWith(TvPreloadManifest.assetPrefix) ||
        value.contains('..') ||
        value.contains('\\') ||
        !<String>{
          'assets/tv_preload/configuration.kyyconfig',
          'assets/tv_preload/metadata.kyymeta',
        }.contains(value)) {
      throw const TvPreloadAssetException('预置资源路径无效');
    }
  }
}

final class TvPreloadAssetException implements Exception {
  const TvPreloadAssetException(this.message);

  final String message;

  @override
  String toString() => 'TvPreloadAssetException($message)';
}
