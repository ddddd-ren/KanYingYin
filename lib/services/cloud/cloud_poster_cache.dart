import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

typedef CloudPosterDownloader = Future<List<int>> Function(String url);
typedef CloudPosterInstallHook = Future<void> Function(String targetPath);

class _LockEntry {
  _LockEntry() : lock = Lock();
  final Lock lock;
  int references = 0;
}

class CloudPosterCache {
  CloudPosterCache(
      {required Directory cacheRoot,
      required CloudPosterDownloader downloader,
      CloudPosterInstallHook? beforeInstall,
      CloudPosterInstallHook? beforeMetadataBackup,
      CloudPosterInstallHook? beforeBackupCleanup})
      : _cacheRoot = cacheRoot,
        _root = CloudCacheDirectories.posterRoot(cacheRoot),
        _downloader = downloader,
        _beforeInstall = beforeInstall,
        _beforeMetadataBackup = beforeMetadataBackup,
        _beforeBackupCleanup = beforeBackupCleanup;

  static const int cacheVersion = 1;
  static final Map<String, _LockEntry> _locks = <String, _LockEntry>{};
  static int get debugLockCount => _locks.length;
  final Directory _cacheRoot;
  final Directory _root;
  final CloudPosterDownloader _downloader;
  final CloudPosterInstallHook? _beforeInstall;
  final CloudPosterInstallHook? _beforeMetadataBackup;
  final CloudPosterInstallHook? _beforeBackupCleanup;

  Future<String> resolve(
      {required String sourceId,
      required String stableId,
      required String url}) async {
    final stableHash = _hash(stableId);
    final versionHash = _hash('$cacheVersion|$url');
    final directory = CloudCacheDirectories.posterSource(_cacheRoot, sourceId);
    final sourceLease = CloudCacheOperationCoordinator.tryBegin(directory);
    if (sourceLease == null) return url;
    final target = p.join(directory.path, '$stableHash.jpg');
    final metadataPath = p.join(directory.path, '$stableHash.url');
    final lockKey = p.join(directory.path, stableHash);
    final entry = _locks.putIfAbsent(lockKey, _LockEntry.new);
    entry.references++;
    try {
      return await entry.lock.synchronized(() async {
        if (!sourceLease.isCurrent) return url;
        final file = File(target);
        final metadata = File(metadataPath);
        if (await file.exists() &&
            await metadata.exists() &&
            await metadata.readAsString() == versionHash) {
          return target;
        }
        File? temporary;
        File? metadataTemporary;
        File? backup;
        File? metadataBackup;
        var imageBackedUp = false;
        var metadataBackedUp = false;
        var imageInstalled = false;
        var metadataInstalled = false;
        try {
          await directory.create(recursive: true);
          final suffix = DateTime.now().microsecondsSinceEpoch;
          temporary = File('$target.$suffix.tmp');
          metadataTemporary = File('$metadataPath.$suffix.tmp');
          backup = File('$target.$suffix.bak');
          metadataBackup = File('$metadataPath.$suffix.bak');
          final bytes = await _downloader(url);
          if (!sourceLease.isCurrent) return url;
          await temporary.writeAsBytes(bytes, flush: true);
          if (!sourceLease.isCurrent) return url;
          await metadataTemporary.writeAsString(versionHash, flush: true);
          if (!sourceLease.isCurrent) return url;
          if (await file.exists()) {
            await file.rename(backup.path);
            imageBackedUp = true;
          }
          await _beforeMetadataBackup?.call(metadataPath);
          if (await metadata.exists()) {
            await metadata.rename(metadataBackup.path);
            metadataBackedUp = true;
          }
          await _beforeInstall?.call(target);
          await temporary.rename(target);
          imageInstalled = true;
          await metadataTemporary.rename(metadataPath);
          metadataInstalled = true;
        } on Object {
          if (imageInstalled && await file.exists()) await file.delete();
          if (metadataInstalled && await metadata.exists()) {
            await metadata.delete();
          }
          if (imageBackedUp && backup != null && await backup.exists()) {
            await backup.rename(target);
            imageBackedUp = false;
          }
          if (metadataBackedUp &&
              metadataBackup != null &&
              await metadataBackup.exists()) {
            await metadataBackup.rename(metadataPath);
            metadataBackedUp = false;
          }
          return await file.exists() && await metadata.exists() ? target : url;
        } finally {
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
          if (metadataTemporary != null && await metadataTemporary.exists()) {
            await metadataTemporary.delete();
          }
          // 未恢复的备份必须保留，避免在异常链中继续破坏旧缓存。
        }
        // 执行到这里说明双文件已经提交；清理失败不得进入上方回滚。
        for (final old in [backup, metadataBackup]) {
          if (!await old.exists()) continue;
          try {
            await _beforeBackupCleanup?.call(old.path);
            await old.delete();
          } on Object catch (error) {
            stderr.writeln('CloudPosterCache: 清理备份失败 ${old.path}: $error');
          }
        }
        return target;
      }).whenComplete(() {
        entry.references--;
        if (entry.references == 0) _locks.remove(lockKey);
      });
    } finally {
      sourceLease.release();
    }
  }

  Future<void> removeOrphans({required Set<String> retainedPaths}) async {
    if (!await _root.exists()) return;
    await for (final entity in _root.list(recursive: true)) {
      if (entity is File &&
          !retainedPaths.contains(entity.path) &&
          !entity.path.endsWith('.url')) {
        await entity.delete();
        final metadata = File('${p.withoutExtension(entity.path)}.url');
        if (await metadata.exists()) await metadata.delete();
      }
    }
  }

  Future<void> clearSource(String sourceId) =>
      CloudCacheOperationCoordinator.clearSource(
        CloudCacheDirectories.posterSource(_cacheRoot, sourceId),
      );

  Future<void> removeSource(String sourceId) => clearSource(sourceId);

  static Future<void> removeSourceFromRoot({
    required Directory cacheRoot,
    required String sourceId,
  }) =>
      clearSourceFromRoot(cacheRoot: cacheRoot, sourceId: sourceId);

  static Future<void> clearSourceFromRoot({
    required Directory cacheRoot,
    required String sourceId,
  }) =>
      CloudCacheOperationCoordinator.clearSource(
        CloudCacheDirectories.posterSource(cacheRoot, sourceId),
      );

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
