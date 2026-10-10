import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_image_selection_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';

void main() {
  test('本地图片可以连续选择并以最新覆盖值保存', () async {
    final index = _MemoryIndexRepository();
    final metadataRepository = _MemoryMetadataRepository();
    final metadata = TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '测试剧集',
      posterUrl: '/default.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 8, 4),
      matchConfidence: 1,
    );
    await index.saveForSource(
      r'D:\Video',
      <LocalMediaIndexItem>[
        _item(r'D:\Video\S01E01.mkv', metadata),
        _item(r'D:\Video\S01E02.mkv', metadata),
      ],
    );
    final service = LocalTmdbImageSelectionService(
      indexRepository: index,
      metadataRepository: metadataRepository,
      client: _FakeImageClient(),
    );

    await service.selectSeriesImage(
      seriesName: '测试剧集',
      kind: TmdbImageKind.poster,
      filePath: '/picked-a.jpg',
    );
    await service.selectSeriesImage(
      seriesName: '测试剧集',
      kind: TmdbImageKind.poster,
      filePath: 'https://image.tmdb.org/t/p/w500/picked-b.jpg',
    );

    expect(
      index.getAll().map((item) => item.tmdb?.imageOverride.poster),
      everyElement('/picked-b.jpg'),
    );
    expect(
      metadataRepository.get('测试剧集')?.imageOverride.poster,
      '/picked-b.jpg',
    );
  });
}

LocalMediaIndexItem _item(String path, TmdbMetadata metadata) {
  return LocalMediaIndexItem(
    path: path,
    name: path.split(r'\').last,
    parentPath: r'D:\Video',
    sourcePath: r'D:\Video',
    size: 100,
    modified: DateTime.utc(2026, 8, 4),
    seriesName: '测试剧集',
    seasonNumber: 1,
    episodeNumber: 1,
    tmdb: metadata,
    indexedAt: DateTime.utc(2026, 8, 4),
  );
}

class _MemoryIndexRepository implements ILocalMediaIndexRepository {
  List<LocalMediaIndexItem> items = <LocalMediaIndexItem>[];

  @override
  List<LocalMediaIndexItem> getAll() =>
      List<LocalMediaIndexItem>.unmodifiable(items);

  @override
  List<LocalMediaIndexItem> getBySourcePath(String sourcePath) =>
      getAll().where((item) => item.sourcePath == sourcePath).toList();

  @override
  List<LocalMediaIndexItem> getBySourceLocation(MediaLocation sourceLocation) =>
      getAll().where((item) => item.sourceLocation == sourceLocation).toList();

  @override
  LocalMediaIndexItem? getByPath(String path) =>
      getAll().where((item) => item.path == path).firstOrNull;

  @override
  LocalMediaIndexItem? getByLocation(MediaLocation location) =>
      getAll().where((item) => item.location == location).firstOrNull;

  @override
  Map<String, String> getDirectoryFingerprints(String sourcePath) =>
      const <String, String>{};

  @override
  Map<String, String> getDirectoryFingerprintsForLocation(
    MediaLocation sourceLocation,
  ) =>
      const <String, String>{};

  @override
  Future<void> saveForSource(
      String sourcePath, List<LocalMediaIndexItem> values) async {
    items = <LocalMediaIndexItem>[...values];
  }

  @override
  Future<void> saveForSourceLocation(
    MediaLocation sourceLocation,
    List<LocalMediaIndexItem> values,
  ) async {
    items = <LocalMediaIndexItem>[...values];
  }

  @override
  Future<void> updateItem(LocalMediaIndexItem item) async {
    final index = items.indexWhere((value) => value.id == item.id);
    if (index < 0) {
      items = <LocalMediaIndexItem>[...items, item];
      return;
    }
    items = <LocalMediaIndexItem>[...items]..[index] = item;
  }

  @override
  Future<void> updateItems(Map<String, LocalMediaIndexItem> values) async {
    items = items.map((item) => values[item.id] ?? item).toList();
  }

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) async {}

  @override
  Future<void> saveDirectoryFingerprintsForLocation(
    MediaLocation sourceLocation,
    Map<String, String> fingerprints,
  ) async {}

  @override
  Future<void> removeSource(String sourcePath) async {
    items = items.where((item) => item.sourcePath != sourcePath).toList();
  }

  @override
  Future<void> removeSourceLocation(MediaLocation sourceLocation) async {
    items =
        items.where((item) => item.sourceLocation != sourceLocation).toList();
  }

  @override
  Future<void> clear() async => items = <LocalMediaIndexItem>[];
}

class _MemoryMetadataRepository implements ITmdbMetadataRepository {
  final Map<String, TmdbMetadata> values = <String, TmdbMetadata>{};

  @override
  TmdbMetadata? get(String mediaKey) => values[mediaKey];

  @override
  Future<void> save(String mediaKey, TmdbMetadata metadata) async {
    values[mediaKey] = metadata;
  }

  @override
  Future<void> remove(String mediaKey) async => values.remove(mediaKey);
}

class _FakeImageClient implements ITmdbClient, ITmdbImageCapabilities {
  @override
  Future<TmdbImageSet> images(
    int id,
    TmdbMediaType mediaType, {
    int? seasonNumber,
    int? episodeNumber,
    String language = 'zh-CN',
  }) async =>
      const TmdbImageSet();

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) =>
      throw UnimplementedError();

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) =>
      throw UnimplementedError();
}
