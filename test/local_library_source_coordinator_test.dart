import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/local_library_source_coordinator.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';

void main() {
  test('扫描期间拒绝删除来源和索引', () async {
    final sources = _SourceRepository();
    final index = _IndexRepository();
    final coordinator = LocalLibrarySourceCoordinator(
      sourceRepository: sources,
      indexRepository: index,
    );

    final removed = await coordinator.removeSource(
      'D:/media',
      scanInProgress: true,
    );

    expect(removed, isFalse);
    expect(sources.removedPaths, isEmpty);
    expect(index.removedSources, isEmpty);
  });

  test('删除来源只清理来源记录和派生索引', () async {
    final sources = _SourceRepository();
    final index = _IndexRepository();
    final coordinator = LocalLibrarySourceCoordinator(
      sourceRepository: sources,
      indexRepository: index,
    );

    final removed = await coordinator.removeSource(
      'D:/media',
      scanInProgress: false,
    );

    expect(removed, isTrue);
    expect(sources.removedPaths, ['D:/media']);
    expect(index.removedSources, ['D:/media']);
  });

  test('批量删除只处理不可用来源', () async {
    final sources = _SourceRepository();
    final index = _IndexRepository();
    final coordinator = LocalLibrarySourceCoordinator(
      sourceRepository: sources,
      indexRepository: index,
      isAvailable: (source) => source.path.endsWith('online'),
    );

    final count = await coordinator.removeUnavailableSources(
      [
        LocalMediaSource.fromPath('D:/online'),
        LocalMediaSource.fromPath('D:/offline'),
      ],
      scanInProgress: false,
    );

    expect(count, 1);
    final normalizedOfflinePath = LocalMediaSource.fromPath('D:/offline').path;
    expect(sources.removedPaths, [normalizedOfflinePath]);
    expect(index.removedSources, [normalizedOfflinePath]);
  });
}

class _SourceRepository implements ILocalMediaSourceRepository {
  final List<String> removedPaths = [];

  @override
  List<LocalMediaSource> getAll() => const [];

  @override
  LocalMediaSource? getByPath(String path) => null;

  @override
  Future<bool> removePath(String path) async {
    removedPaths.add(path);
    return true;
  }

  @override
  Future<void> updateScanSummary({
    required String path,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) async {}

  @override
  Future<LocalMediaSource> upsertPath(String path) async =>
      LocalMediaSource.fromPath(path);
}

class _IndexRepository implements ILocalMediaIndexRepository {
  final List<String> removedSources = [];

  @override
  Future<void> clear() async {}

  @override
  List<LocalMediaIndexItem> getAll() => const [];

  @override
  List<LocalMediaIndexItem> getBySourcePath(String sourcePath) => const [];

  @override
  Map<String, String> getDirectoryFingerprints(String sourcePath) => const {};

  @override
  LocalMediaIndexItem? getByPath(String path) => null;

  @override
  Future<void> removeSource(String sourcePath) async {
    removedSources.add(sourcePath);
  }

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) async {}

  @override
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  ) async {}

  @override
  Future<void> updateItem(LocalMediaIndexItem item) async {}
}
