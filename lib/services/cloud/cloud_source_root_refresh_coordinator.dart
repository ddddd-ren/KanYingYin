import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';

typedef CloudLibraryReload = Future<void> Function();
typedef CloudSourceScan = Future<CloudMediaScanResult> Function(
    String sourceId);

final class CloudSourceRootRefreshException implements Exception {
  const CloudSourceRootRefreshException(this.cause, [this.stackTrace]);

  final Object cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '目录已保存，但媒体库更新失败：$cause';
}

final class CloudSourceRootRefreshCoordinator {
  const CloudSourceRootRefreshCoordinator({
    required CloudLibraryReload reloadLocalLibrary,
    required CloudLibraryReload reloadCloudResources,
    required CloudSourceScan scanSource,
  })  : _reloadLocalLibrary = reloadLocalLibrary,
        _reloadCloudResources = reloadCloudResources,
        _scanSource = scanSource;

  final CloudLibraryReload _reloadLocalLibrary;
  final CloudLibraryReload _reloadCloudResources;
  final CloudSourceScan _scanSource;

  Future<void> refreshSource(String sourceId) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await attempt(_reloadLocalLibrary);
    await attempt(_reloadCloudResources);
    await attempt(() async {
      final result = await _scanSource(sourceId);
      if (result.cancelled) {
        throw StateError('网盘媒体扫描已取消');
      }
      if (result.failures > 0) {
        throw StateError('网盘媒体扫描未完整完成（失败 ${result.failures} 个目录）');
      }
    });
    await attempt(_reloadLocalLibrary);
    await attempt(_reloadCloudResources);

    if (firstError != null) {
      throw CloudSourceRootRefreshException(firstError!, firstStackTrace);
    }
  }
}
