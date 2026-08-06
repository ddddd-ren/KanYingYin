import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/application/local_episode_match_service.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  late _MemoryStorage storage;
  late LocalMediaIndexRepository repository;
  late LocalEpisodeMatchService service;

  setUp(() async {
    storage = _MemoryStorage();
    repository = LocalMediaIndexRepository(storage: storage);
    service = LocalEpisodeMatchService(repository: repository);
    await repository.saveForSource(
      r'D:\Library',
      <LocalMediaIndexItem>[
        _item(r'D:\Library\Show\Season 1\Show.S01E01.mkv'),
        _item(r'D:\Library\Show\Season 1\Show.1080p.mkv'),
      ],
    );
  });

  test('批量保存映射和保留原名并写入手动来源', () async {
    final items = repository.getAll();

    await service.save(
      resourceIds: items.map((item) => item.id),
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.mapped(
          resourceId: items[0].id,
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        ManualEpisodeAssignment.keepOriginal(items[1].id),
      ],
      metadata: _metadata(),
      selectedSeasonNumber: 1,
    );

    final updatedById = <String, LocalMediaIndexItem>{
      for (final item in repository.getAll()) item.id: item,
    };
    final mapped = updatedById[items[0].id]!;
    final kept = updatedById[items[1].id]!;
    expect(mapped.seasonNumber, 1);
    expect(mapped.episodeNumber, 2);
    expect(mapped.manualOverride, isTrue);
    expect(mapped.tmdbMatchOrigin, TmdbMatchOrigin.manual);
    expect(mapped.tmdb?.id, 196285);
    expect(kept.seasonNumber, isNull);
    expect(kept.episodeNumber, isNull);
    expect(kept.manualOverride, isTrue);
    expect(kept.displayTitle, kept.name);
  });

  test('恢复自动识别会清除手动覆盖并重新解析季度目录', () async {
    final original = _item(
      r'D:\Library\Show\Season 2\Show EP03.mkv',
      seasonNumber: 1,
      episodeNumber: 1,
      manualOverride: true,
    );
    await repository
        .saveForSource(r'D:\Library', <LocalMediaIndexItem>[original]);

    await service.save(
      resourceIds: <String>[original.id],
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.restoreAutomatic(original.id),
      ],
      metadata: _metadata(),
      selectedSeasonNumber: 2,
    );

    final restored = repository.getAll().single;
    expect(restored.seasonNumber, 2);
    expect(restored.episodeNumber, 3);
    expect(restored.manualOverride, isFalse);
  });

  test('单集人工匹配可同时更正作品归属且不修改其他视频', () async {
    final items = repository.getAll();
    final target = items.first;
    final sibling = items.last;

    await service.save(
      resourceIds: <String>[target.id],
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.mapped(
          resourceId: target.id,
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      ],
      metadata: _metadata(),
      selectedSeasonNumber: 1,
      seriesNameOverride: '异世界悠闲农家',
    );

    final updatedById = <String, LocalMediaIndexItem>{
      for (final item in repository.getAll()) item.id: item,
    };
    expect(updatedById[target.id]!.seriesName, '异世界悠闲农家');
    expect(updatedById[target.id]!.episodeNumber, 2);
    expect(updatedById[target.id]!.manualOverride, isTrue);
    expect(updatedById[sibling.id]!.seriesName, 'Show');
    expect(updatedById[sibling.id]!.tmdb, isNull);
  });

  test('显式清空季集字段可以 JSON 往返', () {
    final cleared = _item(
      r'D:\Library\Show\Show.S01E01.mkv',
      seasonNumber: 1,
      episodeNumber: 1,
      manualOverride: true,
    ).withEpisodeMapping(
      seasonNumber: null,
      episodeNumber: null,
      manualOverride: true,
      metadata: _metadata(),
      matchOrigin: TmdbMatchOrigin.manual,
    );

    final restored = LocalMediaIndexItem.fromJson(cleared.toJson());
    expect(restored.seasonNumber, isNull);
    expect(restored.episodeNumber, isNull);
    expect(restored.manualOverride, isTrue);
    expect(restored.tmdb?.id, 196285);
  });

  test('批量写入失败后恢复全部索引快照', () async {
    final before = repository.getAll().map(_mappingSnapshot).toList();
    final items = repository.getAll();
    storage.failNextWriteAfterPersist = true;

    await expectLater(
      service.save(
        resourceIds: items.map((item) => item.id),
        assignments: <ManualEpisodeAssignment>[
          ManualEpisodeAssignment.mapped(
            resourceId: items[0].id,
            seasonNumber: 1,
            episodeNumber: 2,
          ),
          ManualEpisodeAssignment.keepOriginal(items[1].id),
        ],
        metadata: _metadata(),
        selectedSeasonNumber: 1,
      ),
      throwsA(isA<StateError>()),
    );

    final reloaded = LocalMediaIndexRepository(storage: storage);
    expect(reloaded.getAll().map(_mappingSnapshot).toList(), before);
  });
}

({
  String id,
  int? seasonNumber,
  int? episodeNumber,
  bool manualOverride,
  int? tmdbId,
}) _mappingSnapshot(LocalMediaIndexItem item) {
  return (
    id: item.id,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    manualOverride: item.manualOverride,
    tmdbId: item.tmdb?.id,
  );
}

LocalMediaIndexItem _item(
  String path, {
  int? seasonNumber,
  int? episodeNumber,
  bool manualOverride = false,
}) {
  final parentPath = path.substring(0, path.lastIndexOf(r'\'));
  return LocalMediaIndexItem(
    path: path,
    name: path.substring(path.lastIndexOf(r'\') + 1),
    parentPath: parentPath,
    sourcePath: r'D:\Library',
    size: 100,
    modified: DateTime.utc(2026, 8, 6),
    seriesName: 'Show',
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    manualOverride: manualOverride,
    indexedAt: DateTime.utc(2026, 8, 6),
  );
}

TmdbMetadata _metadata() {
  return TmdbMetadata(
    id: 196285,
    mediaType: TmdbMediaType.tv,
    title: '异世界悠闲农家',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 6),
    matchConfidence: 1,
    seasons: const <TmdbSeasonMetadata>[
      TmdbSeasonMetadata(
        id: 1,
        seasonNumber: 1,
        name: '第 1 季',
        episodeCount: 2,
        episodes: <TmdbEpisodeMetadata>[
          TmdbEpisodeMetadata(id: 11, episodeNumber: 1, name: '万能农具'),
          TmdbEpisodeMetadata(id: 12, episodeNumber: 2, name: '第一位村民'),
        ],
      ),
      TmdbSeasonMetadata(
        id: 2,
        seasonNumber: 2,
        name: '第 2 季',
        episodeCount: 3,
        episodes: <TmdbEpisodeMetadata>[
          TmdbEpisodeMetadata(id: 23, episodeNumber: 3, name: '新的生活'),
        ],
      ),
    ],
  );
}

final class _MemoryStorage implements LocalMediaIndexStorage {
  final Map<String, Object?> values = <String, Object?>{};
  bool failNextWriteAfterPersist = false;

  @override
  Object? read(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
    if (failNextWriteAfterPersist) {
      failNextWriteAfterPersist = false;
      throw StateError('模拟写入失败');
    }
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
