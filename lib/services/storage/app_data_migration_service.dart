import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:path/path.dart' as p;

class StorageMigrationException implements Exception {
  const StorageMigrationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StorageMigrationResult {
  const StorageMigrationResult({
    required this.fileCount,
    required this.byteCount,
    required this.manifestHash,
  });

  final int fileCount;
  final int byteCount;
  final String manifestHash;
}

class AppDataMigrationService {
  const AppDataMigrationService();

  Future<StorageMigrationResult> migrateDirectory({
    required Directory source,
    required Directory target,
  }) async {
    if (!await source.exists()) {
      await target.create(recursive: true);
      return const StorageMigrationResult(
        fileCount: 0,
        byteCount: 0,
        manifestHash: '',
      );
    }
    if (p.equals(
      p.normalize(source.absolute.path),
      p.normalize(target.absolute.path),
    )) {
      return _manifest(source);
    }
    final temporary = Directory('${target.path}.migrating');
    if (await temporary.exists()) await temporary.delete(recursive: true);
    try {
      await _copyTree(source, temporary);
      final copied = await _manifest(temporary);
      final original = await _manifest(source);
      if (copied.fileCount != original.fileCount ||
          copied.byteCount != original.byteCount ||
          copied.manifestHash != original.manifestHash) {
        throw const StorageMigrationException('迁移校验失败');
      }
      if (await target.exists()) {
        final backup = Directory('${target.path}.backup');
        if (await backup.exists()) await backup.delete(recursive: true);
        await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      return copied;
    } on Object catch (error) {
      if (await temporary.exists()) await temporary.delete(recursive: true);
      if (error is StorageMigrationException) rethrow;
      throw StorageMigrationException('迁移失败：${error.runtimeType}');
    }
  }

  Future<StorageMigrationResult> migrateResolver(
    StoragePathResolver resolver,
  ) async {
    final data = await migrateDirectory(
      source: resolver.legacyDataRoot,
      target: resolver.dataRoot,
    );
    try {
      await migrateDirectory(
        source: resolver.legacyCacheRoot,
        target: resolver.cacheRoot,
      );
    } catch (_) {
      // 数据迁移成功但缓存失败时保留数据目录，缓存可以重建。
    }
    await resolver.save();
    return data;
  }

  Future<void> clearCache(Directory cacheRoot) async {
    if (await cacheRoot.exists()) await cacheRoot.delete(recursive: true);
  }

  Future<void> _copyTree(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyTree(entity, Directory(destination));
      } else if (entity is File) {
        await File(destination).parent.create(recursive: true);
        await entity.copy(destination);
      }
    }
  }

  Future<StorageMigrationResult> _manifest(Directory root) async {
    final rows = <String>[];
    var files = 0;
    var bytes = 0;
    if (!await root.exists()) {
      return const StorageMigrationResult(
        fileCount: 0,
        byteCount: 0,
        manifestHash: '',
      );
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: root.path);
      final length = await entity.length();
      final digest = await sha256.bind(entity.openRead()).first;
      rows.add('$relative|$length|$digest');
      files++;
      bytes += length;
    }
    rows.sort();
    final hash = sha256.convert(utf8.encode(rows.join('\n'))).toString();
    return StorageMigrationResult(
      fileCount: files,
      byteCount: bytes,
      manifestHash: hash,
    );
  }
}
