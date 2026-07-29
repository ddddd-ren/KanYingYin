import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef TransferTemporaryDirectoryProvider = Future<Directory> Function();

final class DecodedScrapedMetadataArchive {
  const DecodedScrapedMetadataArchive({
    required this.payload,
    required this.imageFiles,
    required this.temporaryDirectory,
  });

  final ScrapedMetadataPayload payload;
  final Map<String, File> imageFiles;
  final Directory temporaryDirectory;

  Future<void> dispose() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

final class ScrapedMetadataArchiveCodec {
  ScrapedMetadataArchiveCodec({
    TransferTemporaryDirectoryProvider? temporaryDirectoryProvider,
  }) : _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  static const int maxEntries = maxTransferImages + 3;
  static const int maxImageBytes = 25 * 1024 * 1024;
  static const int maxExtractedBytes = 10 * 1024 * 1024 * 1024;

  final TransferTemporaryDirectoryProvider _temporaryDirectoryProvider;

  Future<File> write({
    required File output,
    required ScrapedMetadataPayload payload,
    required Map<String, File> images,
  }) async {
    if (images.length > maxTransferImages) {
      throw const FormatException('迁移包图片数量超过上限');
    }
    final root = await _temporaryDirectoryProvider();
    await root.create(recursive: true);
    final staging = await root.createTemp('kyymeta-write-');
    final partial = File('${output.path}.partial');
    try {
      final localFile = File(p.join(staging.path, 'local.json'));
      final cloudFile = File(p.join(staging.path, 'cloud.json'));
      await localFile.writeAsString(
        jsonEncode(<String, Object?>{
          'localSources':
              payload.localSources.map((source) => source.toJson()).toList(),
        }),
        encoding: utf8,
        flush: true,
      );
      await cloudFile.writeAsString(
        jsonEncode(<String, Object?>{
          'cloudSources':
              payload.cloudSources.map((source) => source.toJson()).toList(),
        }),
        encoding: utf8,
        flush: true,
      );

      final stagedFiles = <String, File>{
        'local.json': localFile,
        'cloud.json': cloudFile,
      };
      for (final entry in images.entries) {
        _validateImagePath(entry.key);
        if (!await entry.value.exists()) continue;
        final length = await entry.value.length();
        if (length > maxImageBytes) {
          throw const FormatException('迁移包单张图片超过大小上限');
        }
        stagedFiles[entry.key] = entry.value;
      }

      final fileEntries = <Map<String, Object?>>[];
      var totalBytes = 0;
      for (final entry in stagedFiles.entries) {
        final length = await entry.value.length();
        totalBytes += length;
        if (totalBytes > maxExtractedBytes) {
          throw const FormatException('迁移包内容超过大小上限');
        }
        fileEntries.add(<String, Object?>{
          'path': entry.key,
          'length': length,
          'sha256': await _fileSha256(entry.value),
        });
      }
      final manifest = File(p.join(staging.path, 'manifest.json'));
      await manifest.writeAsString(
        jsonEncode(<String, Object?>{
          'format': scrapedMetadataFormat,
          'formatVersion': payload.formatVersion,
          'appVersion': payload.appVersion,
          'exportedAt': payload.exportedAt.toUtc().toIso8601String(),
          'localRecordCount': payload.localSources.fold<int>(
            0,
            (sum, source) => sum + source.records.length,
          ),
          'cloudRecordCount': payload.cloudSources.fold<int>(
            0,
            (sum, source) => sum + source.recordCount,
          ),
          'imageCount': stagedFiles.keys
              .where((path) => path.startsWith('images/'))
              .length,
          'files': fileEntries,
        }),
        encoding: utf8,
        flush: true,
      );

      if (await partial.exists()) await partial.delete();
      await output.parent.create(recursive: true);
      final encoder = ZipFileEncoder()..create(partial.path);
      try {
        await encoder.addFile(manifest, 'manifest.json');
        for (final entry in stagedFiles.entries) {
          await encoder.addFile(entry.value, entry.key);
        }
      } finally {
        await encoder.close();
      }
      if (await output.exists()) await output.delete();
      await partial.rename(output.path);
      return output;
    } finally {
      if (await partial.exists()) await partial.delete();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<DecodedScrapedMetadataArchive> read(File input) async {
    final root = await _temporaryDirectoryProvider();
    await root.create(recursive: true);
    final extracted = await root.createTemp('kyymeta-read-');
    InputFileStream? inputStream;
    try {
      inputStream = InputFileStream(input.path);
      final archive = ZipDecoder().decodeStream(inputStream);
      if (archive.length > maxEntries) {
        throw const FormatException('迁移包文件数量超过上限');
      }

      final normalizedNames = <String>{};
      var totalBytes = 0;
      for (final entry in archive.files) {
        final name = entry.name.replaceAll('\\', '/');
        if (!_isSafeArchivePath(name) || entry.isSymbolicLink) {
          throw const FormatException('迁移包包含不安全路径');
        }
        if (!normalizedNames.add(name.toLowerCase())) {
          throw const FormatException('迁移包包含重复路径');
        }
        if (!entry.isFile) continue;
        if (name.startsWith('images/') && entry.size > maxImageBytes) {
          throw const FormatException('迁移包单张图片超过大小上限');
        }
        totalBytes += entry.size;
        if (totalBytes > maxExtractedBytes) {
          throw const FormatException('迁移包内容超过大小上限');
        }
      }

      for (final entry in archive.files.where((value) => value.isFile)) {
        final name = entry.name.replaceAll('\\', '/');
        final target = File(p.joinAll(<String>[
          extracted.path,
          ...p.posix.split(name),
        ]));
        await target.parent.create(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
      await inputStream.close();
      inputStream = null;

      final manifestFile = File(p.join(extracted.path, 'manifest.json'));
      final localFile = File(p.join(extracted.path, 'local.json'));
      final cloudFile = File(p.join(extracted.path, 'cloud.json'));
      if (!await manifestFile.exists() ||
          !await localFile.exists() ||
          !await cloudFile.exists()) {
        throw const FormatException('迁移包缺少必需文件');
      }
      final manifest = await _readJsonMap(manifestFile);
      if (manifest['format'] != scrapedMetadataFormat ||
          manifest['formatVersion'] != scrapedMetadataFormatVersion) {
        throw const FormatException('不支持的刮削资料迁移格式版本');
      }
      final declaredFiles = manifest['files'];
      if (declaredFiles is! List) {
        throw const FormatException('迁移包清单无效');
      }
      final imageFiles = <String, File>{};
      final declaredPaths = <String>{};
      for (final raw in declaredFiles) {
        if (raw is! Map) throw const FormatException('迁移包清单无效');
        final item = Map<String, Object?>.from(raw);
        final path = item['path'];
        final length = item['length'];
        final expectedHash = item['sha256'];
        if (path is! String ||
            length is! int ||
            expectedHash is! String ||
            !_isSafeArchivePath(path)) {
          throw const FormatException('迁移包清单无效');
        }
        final file = File(p.joinAll(<String>[
          extracted.path,
          ...p.posix.split(path),
        ]));
        if (!await file.exists() ||
            await file.length() != length ||
            await _fileSha256(file) != expectedHash) {
          throw const FormatException('迁移包文件校验失败');
        }
        declaredPaths.add(path);
        if (path.startsWith('images/')) imageFiles[path] = file;
      }
      if (!declaredPaths.containsAll(<String>['local.json', 'cloud.json'])) {
        throw const FormatException('迁移包清单缺少数据文件');
      }

      final localJson = await _readJsonMap(localFile);
      final cloudJson = await _readJsonMap(cloudFile);
      final payload = ScrapedMetadataPayload.fromJson(<String, Object?>{
        'formatVersion': manifest['formatVersion'],
        'exportedAt': manifest['exportedAt'],
        'appVersion': manifest['appVersion'],
        'localSources': localJson['localSources'],
        'cloudSources': cloudJson['cloudSources'],
      });
      return DecodedScrapedMetadataArchive(
        payload: payload,
        imageFiles: Map<String, File>.unmodifiable(imageFiles),
        temporaryDirectory: extracted,
      );
    } on FormatException {
      if (await extracted.exists()) await extracted.delete(recursive: true);
      rethrow;
    } on Object catch (error) {
      if (await extracted.exists()) await extracted.delete(recursive: true);
      throw FormatException('无法读取刮削资料迁移包', error);
    } finally {
      await inputStream?.close();
    }
  }

  static bool _isSafeArchivePath(String value) {
    if (value.isEmpty || value.contains('\u0000')) return false;
    final replaced = value.replaceAll('\\', '/');
    final normalized = p.posix.normalize(replaced);
    return !p.posix.isAbsolute(normalized) &&
        !RegExp(r'^[A-Za-z]:').hasMatch(normalized) &&
        normalized != '..' &&
        !normalized.startsWith('../') &&
        normalized == replaced;
  }

  static void _validateImagePath(String value) {
    if (!_isSafeArchivePath(value) || !value.startsWith('images/')) {
      throw const FormatException('迁移包图片路径无效');
    }
  }

  static Future<String> _fileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<Map<String, Object?>> _readJsonMap(File file) async {
    final decoded = jsonDecode(await file.readAsString(encoding: utf8));
    if (decoded is! Map) throw const FormatException('迁移包 JSON 结构无效');
    return Map<String, Object?>.from(decoded);
  }
}
