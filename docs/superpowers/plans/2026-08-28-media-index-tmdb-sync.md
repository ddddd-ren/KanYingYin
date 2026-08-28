# Media Index and TMDB Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有手动扫描链路中安全继承本地和网盘媒体的 TMDB 绑定，使文件更新、唯一改名移动和新增剧集同步已有刮削资料。

**Architecture:** 本地索引器在保存前合并同路径或唯一文件签名候选的可信状态，随后现有 `LocalTmdbScrapeService` 批量完成不联网的同系列资料继承。网盘协调器复用现有作品记录迁移框架，并通过 `CloudWorkTmdbService` 的无网络静态同步入口把匹配记录回写当前索引；冲突保持待处理，不覆盖既有可信记录。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、Flutter Modular、现有本地/网盘索引仓储、`flutter_test`

---

## File Map

- Modify: `lib/services/local_media_indexer.dart` - 合并同路径更新状态，并执行唯一改名/移动迁移。
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart` - 批量离线继承同系列唯一 TMDB 身份。
- Modify: `lib/pages/local/local_controller.dart` - 在扫描完成后、自动联网刮削前调用离线继承。
- Modify: `lib/services/cloud/cloud_work_tmdb_service.dart` - 提供不依赖 API Key 或客户端构造的索引回写入口。
- Modify: `lib/services/cloud/cloud_work_tmdb_coordinator.dart` - 迁移作品键变化记录，并回写当前索引项。
- Modify: `test/local_media_indexer_test.dart` - 覆盖同路径更新、唯一迁移和歧义拒绝。
- Modify: `test/local_tmdb_integration_test.dart` - 覆盖无 Key 离线继承与身份冲突。
- Modify: `test/local_controller_test.dart` - 固定离线继承先于自动联网刮削的调用位置。
- Modify: `test/cloud_work_tmdb_service_test.dart` - 覆盖作品记录静态回写。
- Modify: `test/cloud_work_tmdb_coordinator_test.dart` - 覆盖新增剧集回写、根信息迁移与冲突。

本轮不新增仓储、后台任务、文件监听、定时轮询、内容哈希或数据模型，也不修改版本、发布文案和安装脚本。依据项目约束，不执行 Git commit。

### Task 1: Preserve Trusted Local Index State

**Files:**
- Modify: `lib/services/local_media_indexer.dart:416-616`
- Test: `test/local_media_indexer_test.dart`

- [ ] **Step 1: Write failing same-path update tests**

在 `test/local_media_indexer_test.dart` 的索引器测试组中加入以下用例；复用现有 `_MemoryMediaIndexRepository`、`_FakeMediaProbe` 和 `_testIndexer`：

```dart
test('同路径文件更新且逻辑身份不变时保留可信 TMDB 状态', () async {
  final dir = await Directory.systemTemp.createTemp('kanyingyin_same_path_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  final video = File(p.join(dir.path, 'Show S01E01.mkv'));
  await video.writeAsString('first');
  final repository = _MemoryMediaIndexRepository();
  final indexer = _testIndexer(
    repository: repository,
    mediaProbe: const _FakeMediaProbe({}),
  );
  await indexer.indexSource(dir.path);
  final metadata = TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.tv,
    title: '剧名',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 28),
    matchConfidence: 1,
  );
  await repository.updateItem(repository.getAll().single.copyWith(
        tmdb: metadata,
        tmdbIdentity: 'tv:42',
        cover: 'cached-poster.jpg',
        scrapeStatus: TmdbScrapeStatus.matched,
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
        tmdbRuleVersion: currentTmdbRuleVersion,
        titleLocked: true,
        posterLocked: true,
        overviewLocked: true,
      ));

  await video.writeAsString('second-version');
  final result = await indexer.indexSource(dir.path);

  final updated = repository.getAll().single;
  expect(result.updatedCount, 1);
  expect(updated.tmdb, metadata);
  expect(updated.effectiveTmdbIdentity, 'tv:42');
  expect(updated.tmdbMatchOrigin, TmdbMatchOrigin.manual);
  expect(updated.titleLocked, isTrue);
  expect(updated.posterLocked, isTrue);
  expect(updated.overviewLocked, isTrue);
  expect(updated.cover, 'cached-poster.jpg');
});

test('同路径重新解析为其他作品时不继承旧 TMDB', () async {
  final dir = await Directory.systemTemp.createTemp('kanyingyin_identity_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  final showDir = Directory(p.join(dir.path, 'Show'));
  await showDir.create();
  final video = File(p.join(showDir.path, 'Show S01E01.mkv'));
  await video.writeAsString('first');
  final repository = _MemoryMediaIndexRepository();
  final overrides = <String, String>{showDir.path.toLowerCase(): '旧作品'};
  final indexer = LocalMediaIndexer(
    repository: repository,
    mediaProbe: const _FakeMediaProbe({}),
    minRecognizedVideoSizeBytes: 0,
    seriesTitleOverrideRepository: _FixedTitleOverrideRepository(overrides),
  );
  await indexer.indexSource(dir.path);
  await repository.updateItem(repository.getAll().single.copyWith(
        tmdb: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '旧作品',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 28),
          matchConfidence: 1,
        ),
        tmdbIdentity: 'tv:42',
        scrapeStatus: TmdbScrapeStatus.matched,
      ));
  overrides[showDir.path.toLowerCase()] = '新作品';
  await video.writeAsString('second-version');

  await indexer.indexSource(dir.path);

  final updated = repository.getAll().single;
  expect(updated.seriesName, '新作品');
  expect(updated.tmdb, isNull);
  expect(updated.effectiveTmdbIdentity, isNull);
  expect(updated.scrapeStatus, TmdbScrapeStatus.none);
});
```

同时在测试文件补充已有项目模块导入：

```dart
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
```

- [ ] **Step 2: Run the same-path tests and confirm the current failure**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart --plain-name '同路径文件更新且逻辑身份不变时保留可信 TMDB 状态'
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart --plain-name '同路径重新解析为其他作品时不继承旧 TMDB'
```

Expected: 第一项因 `fromFile` 重建后 `tmdb`/锁状态丢失而 FAIL；第二项应保持通过或在合并实现后继续通过。

- [ ] **Step 3: Add one shared local-state merge path**

在 `indexSourceLocation` 中把路径命中项保留为 `samePathItem`，构造当前索引项时不再让旧项直接决定解析结果；构造完成后统一调用状态合并：

```dart
final samePathItem = previous.remove(_entryId(entry));
if (samePathItem != null && _isSameEntry(samePathItem, entry)) {
  if (entry.location.isFile &&
      _metadataRefresher.needsRefresh(samePathItem)) {
    indexed.add(await _metadataRefresher.refreshItem(
      samePathItem,
      indexedAt: DateTime.now(),
    ));
    updatedCount++;
  } else {
    final companionChanged = entry.location.isDocument &&
        ((located.subtitlePath != null &&
                located.subtitlePath != samePathItem.subtitlePath) ||
            (located.coverPath != null &&
                located.coverPath != samePathItem.cover));
    indexed.add(samePathItem.copyWith(
      subtitlePath: located.subtitlePath,
      cover: located.coverPath,
      indexedAt: DateTime.now(),
    ));
    if (companionChanged) {
      updatedCount++;
    } else {
      reusedCount++;
    }
  }
  continue;
}

final moveCandidate = samePathItem == null
    ? _uniqueMoveCandidate(
        entry,
        remaining: previous.values,
        currentSignatureCounts: currentMoveSignatureCounts,
      )
    : null;
final inheritedFrom = samePathItem ?? moveCandidate;

final item = entry.location.isFile
    ? await _buildFileItem(
        entry,
        sourceLocation: sourceLocation,
        episodeInfo: effectiveEpisodeInfo,
        seriesNameOverride: _standaloneRootTitle(
          entry,
          sourceLocation: sourceLocation,
          episodeInfo: effectiveEpisodeInfo,
        ),
        enrichMediaInfo: enrichMediaInfo,
        generateThumbnails: generateThumbnails,
      )
    : LocalMediaIndexItem(
        location: entry.location,
        name: entry.name,
        parentLocation: located.parentLocation,
        sourceLocation: sourceLocation,
        size: entry.size,
        modified: entry.modified,
        seriesName: seriesTitleOverride ??
            episodeInfo?.seriesName ??
            p.basename(located.logicalParentPath),
        seasonNumber: episodeInfo?.seasonNumber,
        episodeNumber: episodeInfo?.episodeNumber,
        episodeTitle: episodeInfo?.episodeTitle,
        releaseGroup: episodeInfo?.releaseGroup,
        resolution: episodeInfo?.resolution,
        source: episodeInfo?.source,
        codec: episodeInfo?.codec,
        cover: located.coverPath,
        subtitlePath: located.subtitlePath,
        durationMillis: documentMediaInfo?.duration?.inMilliseconds,
        videoWidth: documentMediaInfo?.width,
        videoHeight: documentMediaInfo?.height,
        pathFingerprint: _entryFingerprint(entry),
        indexedAt: DateTime.now(),
      );

final canUseMoveCandidate = moveCandidate == null ||
    _mediaInfoCompatible(moveCandidate, item);
if (moveCandidate != null && canUseMoveCandidate) {
  previous.remove(moveCandidate.id);
}
final resolvedItem = inheritedFrom == null || !canUseMoveCandidate
    ? item
    : _inheritTrustedState(
        item,
        inheritedFrom,
        allowLogicalRename: moveCandidate != null,
      );
indexed.add(resolvedItem);
if (samePathItem != null) {
  updatedCount++;
  if (!identical(resolvedItem, item)) inheritedCount++;
} else if (moveCandidate != null && canUseMoveCandidate) {
  updatedCount++;
  migratedCount++;
} else {
  addedCount++;
  if (_hasMoveSignatureConflict(
    entry,
    remaining: previous.values,
    currentSignatureCounts: currentMoveSignatureCounts,
  )) {
    migrationConflictCount++;
  }
}
```

把 `_buildFileItem` 的 `oldItem` 参数和其中的旧值回退删除，让所有回退集中在一个合并函数。加入以下最小私有方法：

```dart
LocalMediaIndexItem _inheritTrustedState(
  LocalMediaIndexItem current,
  LocalMediaIndexItem previous, {
  required bool allowLogicalRename,
}) {
  if (!allowLogicalRename && !_logicalIdentityMatches(current, previous)) {
    return current;
  }
  var inherited = current;
  if (previous.manualOverride) {
    inherited = inherited.withEpisodeMapping(
      seriesName: previous.seriesName,
      seasonNumber: previous.seasonNumber,
      episodeNumber: previous.episodeNumber,
      manualOverride: true,
      metadata: previous.tmdb,
      matchOrigin: previous.tmdbMatchOrigin,
    );
  }
  return inherited.copyWith(
    cover: current.cover ?? previous.cover,
    subtitlePath: current.subtitlePath ?? previous.subtitlePath,
    durationMillis: current.durationMillis ?? previous.durationMillis,
    videoWidth: current.videoWidth ?? previous.videoWidth,
    videoHeight: current.videoHeight ?? previous.videoHeight,
    releaseGroup:
        previous.manualOverride ? previous.releaseGroup : current.releaseGroup,
    resolution:
        previous.manualOverride ? previous.resolution : current.resolution,
    source: previous.manualOverride ? previous.source : current.source,
    codec: previous.manualOverride ? previous.codec : current.codec,
    tmdb: previous.tmdb,
    tmdbIdentity: previous.tmdbIdentity,
    titleLocked: previous.titleLocked,
    posterLocked: previous.posterLocked,
    overviewLocked: previous.overviewLocked,
    scrapeStatus: previous.scrapeStatus,
    tmdbMatchOrigin: previous.tmdbMatchOrigin,
    tmdbRuleVersion: previous.tmdbRuleVersion,
    manualOverride: previous.manualOverride,
  );
}

bool _logicalIdentityMatches(
  LocalMediaIndexItem current,
  LocalMediaIndexItem previous,
) {
  if (previous.manualOverride) return true;
  final currentEpisode = (current.seasonNumber ?? 0) > 0 &&
      (current.episodeNumber ?? 0) > 0;
  final previousEpisode = (previous.seasonNumber ?? 0) > 0 &&
      (previous.episodeNumber ?? 0) > 0;
  if (currentEpisode != previousEpisode) return false;
  if (_normalizeSeries(current.seriesName) !=
      _normalizeSeries(previous.seriesName)) {
    return false;
  }
  return !currentEpisode ||
      (current.seasonNumber == previous.seasonNumber &&
          current.episodeNumber == previous.episodeNumber);
}

String _normalizeSeries(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
```

- [ ] **Step 4: Run the same-path tests and existing indexer suite**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart
```

Expected: PASS；未变化目录复用、取消扫描和删除文件用例保持通过。

- [ ] **Step 5: Write failing unique rename/move tests**

继续在 `test/local_media_indexer_test.dart` 加入：

```dart
test('唯一大小和修改时间候选在改名后继承 TMDB 状态', () async {
  final dir = await Directory.systemTemp.createTemp('kanyingyin_move_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  final oldFile = File(p.join(dir.path, 'Show S01E01.mkv'));
  await oldFile.writeAsString('same-bytes');
  final repository = _MemoryMediaIndexRepository();
  final indexer = _testIndexer(
    repository: repository,
    mediaProbe: const _FakeMediaProbe({}),
  );
  await indexer.indexSource(dir.path);
  final original = repository.getAll().single;
  await repository.updateItem(original.copyWith(
        tmdb: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '剧名',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 28),
          matchConfidence: 1,
        ),
        tmdbIdentity: 'tv:42',
        scrapeStatus: TmdbScrapeStatus.matched,
      ));
  final renamed = await oldFile.rename(p.join(dir.path, 'Renamed S01E01.mkv'));
  await renamed.setLastModified(original.modified);

  final result = await indexer.indexSource(dir.path);

  expect(result.addedCount, 0);
  expect(result.removedCount, 0);
  expect(repository.getAll().single.path, renamed.path);
  expect(repository.getAll().single.effectiveTmdbIdentity, 'tv:42');
});

test('唯一文件签名但媒体时长冲突时不迁移 TMDB', () async {
  final dir = await Directory.systemTemp.createTemp('kanyingyin_media_conflict_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  final oldFile = File(p.join(dir.path, 'Show S01E01.mkv'));
  final newPath = p.join(dir.path, 'Renamed S01E01.mkv');
  await oldFile.writeAsString('same-bytes');
  final repository = _MemoryMediaIndexRepository();
  final indexer = _testIndexer(
    repository: repository,
    mediaProbe: _FakeMediaProbe(<String, LocalMediaInfo>{
      oldFile.path: const LocalMediaInfo(duration: Duration(minutes: 20)),
      newPath: const LocalMediaInfo(duration: Duration(minutes: 40)),
    }),
  );
  await indexer.indexSource(dir.path, enrichMediaInfo: true);
  final original = repository.getAll().single;
  await repository.updateItem(original.copyWith(
        tmdb: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '剧名',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 28),
          matchConfidence: 1,
        ),
        tmdbIdentity: 'tv:42',
        scrapeStatus: TmdbScrapeStatus.matched,
      ));
  final renamed = await oldFile.rename(newPath);
  await renamed.setLastModified(original.modified);

  final result = await indexer.indexSource(
    dir.path,
    enrichMediaInfo: true,
  );

  expect(result.addedCount, 1);
  expect(result.removedCount, 1);
  expect(repository.getAll().single.tmdb, isNull);
  expect(repository.getAll().single.durationMillis,
      const Duration(minutes: 40).inMilliseconds);
});

test('重复大小和修改时间候选存在歧义时不迁移 TMDB', () async {
  final dir = await Directory.systemTemp.createTemp('kanyingyin_ambiguous_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  final modified = DateTime.utc(2026, 8, 28, 8);
  final first = File(p.join(dir.path, 'Show S01E01.mkv'));
  final second = File(p.join(dir.path, 'Show S01E02.mkv'));
  await first.writeAsString('same-size');
  await second.writeAsString('same-size');
  await first.setLastModified(modified);
  await second.setLastModified(modified);
  final repository = _MemoryMediaIndexRepository();
  final indexer = _testIndexer(
    repository: repository,
    mediaProbe: const _FakeMediaProbe({}),
  );
  await indexer.indexSource(dir.path);
  for (final item in repository.getAll()) {
    await repository.updateItem(item.copyWith(
      tmdb: TmdbMetadata(
        id: item.episodeNumber!,
        mediaType: TmdbMediaType.tv,
        title: '剧名',
        language: 'zh-CN',
        matchedAt: modified,
        matchConfidence: 1,
      ),
      tmdbIdentity: 'tv:${item.episodeNumber}',
      scrapeStatus: TmdbScrapeStatus.matched,
    ));
  }
  final renamedFirst = await first.rename(p.join(dir.path, 'A S01E03.mkv'));
  final renamedSecond = await second.rename(p.join(dir.path, 'B S01E04.mkv'));
  await renamedFirst.setLastModified(modified);
  await renamedSecond.setLastModified(modified);

  final result = await indexer.indexSource(dir.path);

  expect(result.addedCount, 2);
  expect(result.removedCount, 2);
  expect(repository.getAll().map((item) => item.tmdb), everyElement(isNull));
});
```

- [ ] **Step 6: Run rename tests and confirm they fail before migration logic**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart --plain-name '唯一大小和修改时间候选在改名后继承 TMDB 状态'
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart --plain-name '唯一文件签名但媒体时长冲突时不迁移 TMDB'
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart --plain-name '重复大小和修改时间候选存在歧义时不迁移 TMDB'
```

Expected: 唯一迁移用例 FAIL，歧义用例保持不误继承。

- [ ] **Step 7: Implement unique move-candidate selection**

在处理 `files` 前统计当前签名数量：

```dart
final currentMoveSignatureCounts = <String, int>{};
for (final located in files) {
  final signature = _moveSignature(
    located.entry.size,
    located.entry.modified,
  );
  currentMoveSignatureCounts.update(
    signature,
    (count) => count + 1,
    ifAbsent: () => 1,
  );
}
```

在 `LocalMediaIndexer` 中加入候选和媒体信息约束：

```dart
LocalMediaIndexItem? _uniqueMoveCandidate(
  LocalMediaEntry entry, {
  required Iterable<LocalMediaIndexItem> remaining,
  required Map<String, int> currentSignatureCounts,
}) {
  final signature = _moveSignature(entry.size, entry.modified);
  if (currentSignatureCounts[signature] != 1) return null;
  final matches = remaining
      .where(
        (item) => _moveSignature(item.size, item.modified) == signature,
      )
      .take(2)
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

String _moveSignature(int size, DateTime modified) =>
    '$size|${modified.millisecondsSinceEpoch}';

bool _mediaInfoCompatible(
  LocalMediaIndexItem previous,
  LocalMediaIndexItem current,
) {
  if (previous.durationMillis != null &&
      current.durationMillis != null &&
      previous.durationMillis != current.durationMillis) {
    return false;
  }
  if (previous.videoWidth != null &&
      current.videoWidth != null &&
      previous.videoWidth != current.videoWidth) {
    return false;
  }
  if (previous.videoHeight != null &&
      current.videoHeight != null &&
      previous.videoHeight != current.videoHeight) {
    return false;
  }
  return true;
}

bool _hasMoveSignatureConflict(
  LocalMediaEntry entry, {
  required Iterable<LocalMediaIndexItem> remaining,
  required Map<String, int> currentSignatureCounts,
}) {
  final signature = _moveSignature(entry.size, entry.modified);
  final oldMatches = remaining
      .where(
        (item) => _moveSignature(item.size, item.modified) == signature,
      )
      .take(2)
      .length;
  return oldMatches > 0 &&
      (oldMatches > 1 || currentSignatureCounts[signature] != 1);
}
```

在文件处理循环前声明计数，并用现有 `AppLogger` 输出来源 ID 与计数，不输出路径、凭据或令牌：

```dart
var inheritedCount = 0;
var migratedCount = 0;
var migrationConflictCount = 0;

AppLogger().i(
  'LocalMediaIndexer: source=${sourceLocation.stableId} '
  'inherited=$inheritedCount migrated=$migratedCount '
  'migrationConflicts=$migrationConflictCount',
);
```

- [ ] **Step 8: Run all local indexer tests**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart
```

Expected: PASS。

### Task 2: Inherit Local Series Metadata Offline

**Files:**
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart:50-62`
- Modify: `lib/pages/local/local_controller.dart:1035-1044`
- Test: `test/local_tmdb_integration_test.dart`
- Test: `test/local_controller_test.dart`

- [ ] **Step 1: Write failing offline-inheritance service tests**

在 `test/local_tmdb_integration_test.dart` 加入：

```dart
test('无 API Key 时新增剧集继承同系列唯一 TMDB 身份', () async {
  final metadata = TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.tv,
    title: '剧名',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 28),
    matchConfidence: 1,
  );
  final anchor = _item('Show S01E01.mkv', seasonNumber: 1).copyWith(
    tmdb: metadata,
    tmdbIdentity: 'tv:42',
    scrapeStatus: TmdbScrapeStatus.matched,
    tmdbMatchOrigin: TmdbMatchOrigin.manual,
    tmdbRuleVersion: currentTmdbRuleVersion,
    titleLocked: true,
  );
  final pending = _item('Show S01E02.mkv', seasonNumber: 1);
  final index = _MemoryIndexRepository(<LocalMediaIndexItem>[anchor, pending]);
  final service = LocalTmdbScrapeService(
    indexRepository: index,
    metadataRepository: _MemoryMetadataRepository(),
    clientFactory: (_) => _NeverCalledClient(),
  );

  final inherited = await service.inheritMatchedSeriesMetadata();

  final updated = index.getByPath(pending.path)!;
  expect(inherited, 1);
  expect(updated.tmdb, metadata);
  expect(updated.effectiveTmdbIdentity, 'tv:42');
  expect(updated.seasonNumber, pending.seasonNumber);
  expect(updated.tmdbMatchOrigin, TmdbMatchOrigin.manual);
  expect(updated.titleLocked, isTrue);
});

test('同系列存在多个 TMDB 身份时不执行离线继承', () async {
  LocalMediaIndexItem matched(String name, int id) =>
      _item(name, seasonNumber: 1).copyWith(
        tmdb: TmdbMetadata(
          id: id,
          mediaType: TmdbMediaType.tv,
          title: '剧名',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 28),
          matchConfidence: 1,
        ),
        tmdbIdentity: 'tv:$id',
        scrapeStatus: TmdbScrapeStatus.matched,
      );
  final pending = _item('Show S01E03.mkv', seasonNumber: 1);
  final index = _MemoryIndexRepository(<LocalMediaIndexItem>[
    matched('Show S01E01.mkv', 42),
    matched('Show S01E02.mkv', 99),
    pending,
  ]);
  final service = LocalTmdbScrapeService(
    indexRepository: index,
    metadataRepository: _MemoryMetadataRepository(),
    clientFactory: (_) => _NeverCalledClient(),
  );

  expect(await service.inheritMatchedSeriesMetadata(), 0);
  expect(index.getByPath(pending.path)!.tmdb, isNull);
});
```

测试辅助客户端明确禁止网络路径：

```dart
class _NeverCalledClient implements ITmdbClient {
  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) => throw StateError('离线继承不应调用 TMDB');

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) => throw StateError('离线继承不应调用 TMDB');
}
```

- [ ] **Step 2: Run service tests and confirm the missing-method failure**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_tmdb_integration_test.dart --plain-name '无 API Key 时新增剧集继承同系列唯一 TMDB 身份'
```

Expected: 编译 FAIL，提示 `inheritMatchedSeriesMetadata` 未定义。

- [ ] **Step 3: Implement batched offline inheritance in the existing service**

在 `LocalTmdbScrapeService` 加入：

```dart
Future<int> inheritMatchedSeriesMetadata() async {
  final groups = <String, List<LocalMediaIndexItem>>{};
  for (final item in indexRepository.getAll()) {
    final key = item.seriesName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (key.isEmpty) continue;
    (groups[key] ??= <LocalMediaIndexItem>[]).add(item);
  }

  final updates = <String, LocalMediaIndexItem>{};
  for (final items in groups.values) {
    final matched = items
        .where(
          (item) =>
              item.scrapeStatus == TmdbScrapeStatus.matched &&
              item.tmdb != null &&
              item.effectiveTmdbIdentity != null,
        )
        .toList(growable: false);
    if (matched.isEmpty) continue;
    final identities = matched
        .map((item) => item.effectiveTmdbIdentity!)
        .toSet();
    final policies = matched
        .map(
          (item) => '${item.tmdbMatchOrigin.name}|'
              '${item.titleLocked}|${item.posterLocked}|'
              '${item.overviewLocked}',
        )
        .toSet();
    if (identities.length != 1 || policies.length != 1) continue;
    final anchor = matched.reduce(
      (first, second) =>
          first.indexedAt.isAfter(second.indexedAt) ? first : second,
    );
    for (final item in items) {
      if (item.tmdb != null ||
          item.manualOverride ||
          _hasProtectedMatch(item)) {
        continue;
      }
      updates[item.id] = item.copyWith(
        tmdb: anchor.tmdb,
        tmdbIdentity: anchor.effectiveTmdbIdentity,
        scrapeStatus: TmdbScrapeStatus.matched,
        tmdbMatchOrigin: anchor.tmdbMatchOrigin,
        tmdbRuleVersion: anchor.tmdbRuleVersion,
        titleLocked: anchor.titleLocked,
        posterLocked: anchor.posterLocked,
        overviewLocked: anchor.overviewLocked,
      );
    }
  }
  await indexRepository.updateItems(updates);
  return updates.length;
}
```

该方法只读写本地索引仓储，不接收 API Key，不创建 TMDB 客户端，也不修改新剧集的路径、季号和集号。

- [ ] **Step 4: Run the local TMDB integration suite**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_tmdb_integration_test.dart
```

Expected: PASS；原有人工匹配隔离、强制重刮和海报下载用例保持通过。

- [ ] **Step 5: Write a failing controller ordering test**

扩展 `test/local_controller_test.dart` 中现有 `_RecordingLocalTmdbScrapeService`：

```dart
int offlineInheritanceCalls = 0;

@override
Future<int> inheritMatchedSeriesMetadata() async {
  offlineInheritanceCalls++;
  return 0;
}
```

在本地索引刷新用例旁加入：

```dart
test('本地扫描完成后即使无 API Key 也执行离线 TMDB 继承', () async {
  final dir = await Directory.systemTemp.createTemp('kanyingyin_offline_tmdb_');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  await File('${dir.path}${Platform.pathSeparator}Show S01E02.mkv')
      .writeAsString('video');
  final indexRepository = _MemoryMediaIndexRepository();
  final service = _RecordingLocalTmdbScrapeService(indexRepository);
  final controller = LocalController(
    scanner: _ImmediateScanner(const <LocalFileItem>[]),
    mediaIndexer: _FakeMediaIndexer(indexRepository),
    mediaIndexRepository: indexRepository,
    mediaSourceRepository: _MemoryMediaSourceRepository(),
    tmdbScrapeService: service,
    tmdbApiKeyProvider: TmdbApiKeyProvider(userKeyReader: () => ''),
    preferences: _preferences(),
  );

  await controller.setRootDirectory(dir.path);
  await controller.refreshLocalLibraryIndex();

  expect(service.offlineInheritanceCalls, 1);
  expect(service.seriesNames, isEmpty);
});
```

- [ ] **Step 6: Call offline inheritance before automatic scraping**

将 `refreshLocalLibraryIndex` 扫描成功分支改为顺序等待离线继承，再刷新内存列表，最后维持现有异步自动刮削：

```dart
_reloadMediaSourcesSafe();
_reloadLocalLibraryIndexSafe();
if (!scanCancelled) {
  final inherited =
      await _tmdbScrapeService.inheritMatchedSeriesMetadata();
  if (inherited > 0) {
    _reloadLocalLibraryIndexSafe();
    AppLogger().i(
      'LocalController: inherited TMDB metadata for $inherited index items',
    );
  }
  final failureText = libraryIndexFailures.isEmpty
      ? ''
      : '，${libraryIndexFailures.length} 项需要处理';
  libraryIndexSummary =
      '媒体库已更新：$totalCount 个视频，$localLibrarySeriesCount 个系列$failureText';
  _autoScrapeTmdbAfterScan();
}
```

- [ ] **Step 7: Run controller and local TMDB tests together**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_controller_test.dart test/local_tmdb_integration_test.dart
```

Expected: PASS；无 Key 测试中 `seriesNames` 为空，证明未进入网络刮削。

### Task 3: Rebind and Backfill Cloud Work Metadata

**Files:**
- Modify: `lib/services/cloud/cloud_work_tmdb_service.dart:334-375`
- Modify: `lib/services/cloud/cloud_work_tmdb_coordinator.dart:81-157`
- Modify: `lib/services/cloud/cloud_work_tmdb_coordinator.dart:159-240`
- Test: `test/cloud_work_tmdb_service_test.dart`
- Test: `test/cloud_work_tmdb_coordinator_test.dart`

- [ ] **Step 1: Write a failing static index-backfill test**

在 `test/cloud_work_tmdb_service_test.dart` 加入：

```dart
test('已有作品记录可在不请求 TMDB 时回写当前索引项', () async {
  final indexRepository = CloudMediaIndexRepository(
    storage: MemoryCloudMediaIndexStorage(),
  );
  final work = _work(seasonNumbers: const <int>[1]);
  await indexRepository.replaceSource(
    work.sourceId,
    <CloudMediaIndexItem>[
      _item(work, id: 's1e1', seasonNumber: 1),
    ],
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    <String>[work.root.id],
  );
  final record = CloudWorkTmdbRecord.matched(
    sourceId: work.sourceId,
    workKey: work.workKey,
    workRootId: work.root.id,
    workRootPath: work.root.remotePath,
    remoteName: work.remoteName,
    metadata: TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: 'TMDB 中文标题',
      overview: '简介',
      rating: 8.8,
      posterUrl: '/poster.jpg',
      genres: const <String>['剧情'],
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 8, 28),
      matchConfidence: 1,
    ),
    checkedAt: DateTime.utc(2026, 8, 28),
    posterCachePath: 'cached-poster.jpg',
  );

  final count = await CloudWorkTmdbService.syncMatchedRecordToIndex(
    indexRepository: indexRepository,
    work: work,
    record: record,
  );

  final updated = (await indexRepository.getBySource(work.sourceId)).single;
  expect(count, 1);
  expect(updated.tmdbId, 42);
  expect(updated.tmdbTitle, 'TMDB 中文标题');
  expect(updated.tmdbOverview, '简介');
  expect(updated.tmdbRating, 8.8);
  expect(updated.posterCachePath, 'cached-poster.jpg');
  expect(updated.tmdbGenres, contains('剧情'));
  expect(updated.size, 200);
  expect(updated.seasonNumber, 1);
  expect(updated.episodeNumber, 1);
});
```

该用例直接复用本文件现有 `_work` 和 `_item` 夹具，不新增共享测试抽象。

- [ ] **Step 2: Run the backfill test and confirm the missing-method failure**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/cloud_work_tmdb_service_test.dart --plain-name '已有作品记录可在不请求 TMDB 时回写当前索引项'
```

Expected: 编译 FAIL，提示 `syncMatchedRecordToIndex` 未定义。

- [ ] **Step 3: Extract the existing index replacement into a static no-network entry**

在 `CloudWorkTmdbService` 中保留实例 API，并让它委托静态方法：

```dart
Future<int> syncRecordToIndex(
  CloudWorkIdentity work,
  CloudWorkTmdbRecord record,
) {
  return syncMatchedRecordToIndex(
    indexRepository: _indexRepository,
    work: work,
    record: record,
  );
}

static Future<int> syncMatchedRecordToIndex({
  required CloudMediaIndexRepository indexRepository,
  required CloudWorkIdentity work,
  required CloudWorkTmdbRecord record,
}) {
  final metadata = record.metadata;
  if (record.status != CloudWorkTmdbStatus.matched || metadata == null) {
    return Future<int>.value(0);
  }
  return indexRepository.updateMatching(
    work.sourceId,
    (item) => item.workKey == work.workKey,
    (item) => _replaceMetadata(
      item.withEffectiveWorkTitle(metadata.title),
      metadata,
      record.posterCachePath,
    ),
  );
}

static CloudMediaIndexItem _replaceMetadata(
  CloudMediaIndexItem item,
  TmdbMetadata metadata,
  String? posterCachePath,
) {
  return item.replaceTmdb(
    tmdbId: metadata.id,
    tmdbTitle: metadata.title,
    tmdbOriginalTitle: metadata.originalTitle,
    tmdbOverview: metadata.overview,
    tmdbRating: metadata.rating,
    tmdbPosterUrl: metadata.posterUrl,
    tmdbBackdropUrl: metadata.backdropUrl,
    tmdbGenres: metadata.genres,
    posterCachePath: posterCachePath,
  );
}
```

现有 `_syncIndex` 改为调用该静态方法所用的同一替换逻辑；不构造第二套同步服务。

- [ ] **Step 4: Run the cloud work service suite**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/cloud_work_tmdb_service_test.dart
```

Expected: PASS。

- [ ] **Step 5: Write failing coordinator backfill and rebind tests**

在 `test/cloud_work_tmdb_coordinator_test.dart` 加入：

```dart
test('无 API Key 时已有作品记录仍回写新增索引剧集', () async {
  final fixture = _Fixture(apiKey: '');
  final work = _work('work-id');
  await fixture.repository.upsert(_workRecord(
    work,
    origin: TmdbMatchOrigin.manual,
    ruleVersion: currentTmdbRuleVersion,
  ));
  await fixture.indexRepository.replaceSource(
    work.sourceId,
    <CloudMediaIndexItem>[_indexItem(work)],
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    <String>[work.root.id],
  );

  await fixture.coordinator.loadAndSchedule(_tree(<CloudWorkIdentity>[work]));

  final updated =
      (await fixture.indexRepository.getBySource(work.sourceId)).single;
  expect(updated.tmdbId, 42);
  expect(updated.tmdbTitle, work.displayTitle);
  expect(fixture.client.searchCalls, 0);
  expect(fixture.client.detailCalls, 0);
});

test('作品键和路径变化但根 ID 唯一时迁移匹配记录', () async {
  final fixture = _Fixture(apiKey: '');
  final work = _work(
    'stable-root-id',
    rootPath: '/影视/新目录',
  );
  await fixture.repository.upsert(
    CloudWorkTmdbRecord.matched(
      sourceId: work.sourceId,
      workKey: 'quark-a|work|old-key',
      workRootId: work.root.id,
      workRootPath: '/影视/旧目录',
      remoteName: '旧目录',
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: '规范剧名',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 8, 27),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 8, 27),
      tmdbMatchOrigin: TmdbMatchOrigin.manual,
    ),
  );

  await fixture.coordinator.loadAndSchedule(_tree(<CloudWorkIdentity>[work]));

  final migrated = fixture.coordinator.recordsByWorkKey[work.workKey]!;
  expect(migrated.status, CloudWorkTmdbStatus.matched);
  expect(migrated.metadata?.id, 42);
  expect(migrated.workRootId, work.root.id);
  expect(migrated.workRootPath, work.root.remotePath);
  expect(migrated.tmdbMatchOrigin, TmdbMatchOrigin.manual);
});

test('相同根候选包含不同 TMDB 身份时生成冲突记录', () async {
  final fixture = _Fixture(apiKey: '');
  final work = _work('stable-root-id', rootPath: '/影视/新目录');
  for (final id in <int>[42, 99]) {
    await fixture.repository.upsert(
      CloudWorkTmdbRecord.matched(
        sourceId: work.sourceId,
        workKey: 'quark-a|work|old-$id',
        workRootId: work.root.id,
        workRootPath: '/影视/旧目录-$id',
        remoteName: '旧目录-$id',
        metadata: TmdbMetadata(
          id: id,
          mediaType: TmdbMediaType.tv,
          title: '规范剧名',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 27),
          matchConfidence: 1,
        ),
        checkedAt: DateTime.utc(2026, 8, 27),
      ),
    );
  }

  await fixture.coordinator.loadAndSchedule(_tree(<CloudWorkIdentity>[work]));

  expect(
    fixture.coordinator.recordsByWorkKey[work.workKey]!.status,
    CloudWorkTmdbStatus.conflict,
  );
  expect(fixture.client.searchCalls, 0);
});
```

扩展现有 `_work` 夹具以允许显式根路径，默认行为不变：

```dart
CloudWorkIdentity _work(
  String rootId, {
  String displayTitle = '规范剧名',
  String? rootPath,
}) {
  final root = CloudFileEntry(
    id: rootId,
    remotePath: rootPath ?? '/影视/$rootId',
    name: displayTitle,
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  final workKey = 'quark-a|work|$rootId';
  return CloudWorkIdentity(
    sourceId: 'quark-a',
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: displayTitle,
    titleCandidates: <String>[displayTitle],
    seasons: <CloudSeasonIdentity>[
      for (var season = 1; season <= 2; season++)
        CloudSeasonIdentity(
          workKey: workKey,
          seasonNumber: season,
          displayName: '$displayTitle 第 $season 季',
          remoteDirectories: const <CloudFileEntry>[],
          episodes: <CloudEpisodeIdentity>[
            CloudEpisodeIdentity(
              entry: CloudFileEntry(
                id: 's${season}e1',
                remotePath:
                    '${root.remotePath}/第$season季/s${season}e1.mkv',
                name: 's${season}e1.mkv',
                size: 200,
                modifiedAt: null,
                isDirectory: false,
              ),
              remoteName: 's${season}e1.mkv',
              displayName: '$displayTitle S0${season}E01.mkv',
              seasonNumber: season,
              episodeNumber: 1,
              releaseTags: const MediaReleaseTags(),
            ),
          ],
        ),
    ],
  );
}
```

- [ ] **Step 6: Run coordinator tests and confirm the new failures**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/cloud_work_tmdb_coordinator_test.dart --plain-name '无 API Key 时已有作品记录仍回写新增索引剧集'
& 'D:\flutter\bin\flutter.bat' test test/cloud_work_tmdb_coordinator_test.dart --plain-name '作品键和路径变化但根 ID 唯一时迁移匹配记录'
& 'D:\flutter\bin\flutter.bat' test test/cloud_work_tmdb_coordinator_test.dart --plain-name '相同根候选包含不同 TMDB 身份时生成冲突记录'
```

Expected: 回写和根 ID 迁移用例 FAIL；冲突用例不得自动选中任一身份。

- [ ] **Step 7: Extend the existing work-record migration conservatively**

保留 `_migrateReclassifiedWorkRecords` 的旧式电影键转电视剧兼容规则，在候选过滤中优先加入当前设计的严格根匹配和媒体类型判断：

```dart
final expectedMediaType = work.seasons.isEmpty
    ? TmdbMediaType.movie
    : TmdbMediaType.tv;
final candidates = stored.where((record) {
  final metadata = record.metadata;
  if (record.workKey == work.workKey ||
      record.status != CloudWorkTmdbStatus.matched ||
      metadata?.mediaType != expectedMediaType) {
    return false;
  }
  final recordRoot = _normalizePath(record.workRootPath);
  final sameRoot = record.workRootId == work.root.id ||
      recordRoot == workRoot;
  if (sameRoot) return true;

  final legacyTvReclassification = expectedMediaType == TmdbMediaType.tv &&
      (recordRoot == existingRoot ||
          (recordRoot.startsWith(prefix) &&
              _workTitlesOverlap(work, record)));
  return legacyTvReclassification;
}).toList(growable: false);
```

删除方法开头对 `work.seasons.isEmpty` 的直接跳过。身份集合、手动来源优先、`checkedAt` 最新优先和冲突记录构造继续复用现有实现；迁移只 `upsert` 新 `workKey`，不删除旧记录。

- [ ] **Step 8: Backfill matched records before checking the API Key**

在 `loadAndSchedule` 完成作品记录和旧记录迁移后、读取 `apiKey` 前加入：

```dart
var syncedIndexItems = 0;
for (final work in uniqueWorks.values) {
  if (generation != _generation) return;
  final record = _records[work.workKey];
  if (record == null) continue;
  syncedIndexItems += await CloudWorkTmdbService.syncMatchedRecordToIndex(
    indexRepository: _indexRepository,
    work: work,
    record: record,
  );
}
if (syncedIndexItems > 0) {
  AppLogger().i(
    'CloudWorkTmdbCoordinator: source=${tree.sourceId} '
    'syncedIndexItems=$syncedIndexItems',
  );
}

final apiKey = _apiKeyProvider().trim();
if (apiKey.isEmpty) return;
```

若文件尚未导入日志工具，加入项目现有导入：

```dart
import 'package:kanyingyin/utils/logger.dart';
```

- [ ] **Step 9: Run all cloud TMDB tests**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/cloud_work_tmdb_service_test.dart test/cloud_work_tmdb_coordinator_test.dart test/cloud_work_tmdb_repository_test.dart test/cloud_work_tmdb_record_test.dart
```

Expected: PASS；旧式记录迁移、规则版本刷新、无 Key 作品树和 TMDB 失败保留索引用例均保持通过。

### Task 4: Regression and Delivery-Gate Verification

**Files:**
- Verify only: production and test files listed above

- [ ] **Step 1: Format only the touched Dart files**

Run:

```powershell
& 'D:\flutter\bin\dart.bat' format lib/services/local_media_indexer.dart lib/services/tmdb/local_tmdb_scrape_service.dart lib/pages/local/local_controller.dart lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_work_tmdb_coordinator.dart test/local_media_indexer_test.dart test/local_tmdb_integration_test.dart test/local_controller_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_work_tmdb_coordinator_test.dart
```

Expected: 命令退出码为 `0`，不格式化其他文件。

- [ ] **Step 2: Run the focused regression set**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test test/local_media_indexer_test.dart test/local_tmdb_integration_test.dart test/local_controller_test.dart test/cloud_media_indexer_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_work_tmdb_coordinator_test.dart test/cloud_work_tmdb_repository_test.dart test/cloud_work_tmdb_record_test.dart
```

Expected: PASS，退出码为 `0`。

- [ ] **Step 3: Run the complete test suite**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test
```

Expected: PASS。若 Windows 本机出现已知的测试监听器 `127.0.0.1` / `errno 121`，按测试文件串行重跑失败项；只有完整套件实际通过时才报告完整测试通过。

- [ ] **Step 4: Run static analysis**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' analyze
```

Expected: `No issues found!`，退出码为 `0`。

- [ ] **Step 5: Build Windows Release**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' build windows --release
```

Expected: `build/windows/x64/runner/Release/kanyingyin.exe` 生成成功。此步骤只验证构建，不生成 Inno Setup 安装器、不安装、不发布，也不触及已暂停的 Android TV 流程。

- [ ] **Step 6: Perform adversarial scope review**

Run:

```powershell
git diff --check
git status --short
git diff -- lib/services/local_media_indexer.dart lib/services/tmdb/local_tmdb_scrape_service.dart lib/pages/local/local_controller.dart lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_work_tmdb_coordinator.dart test/local_media_indexer_test.dart test/local_tmdb_integration_test.dart test/local_controller_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_work_tmdb_coordinator_test.dart
```

Expected: `git diff --check` 无输出；仅审查本轮相关 diff，不覆盖或回退工作区既有修改。逐项确认：取消扫描不提交部分结果、读取失败保留旧索引、无 Key 不构造网络客户端、迁移冲突不覆盖可信绑定、逐视频季集映射不被作品资料回写改变、未删除任何原始媒体文件。

- [ ] **Step 7: Record remaining real-device checks without claiming completion**

实现和自动化验证完成后，交付说明中单列以下未自动验证项：本地文件改名、同路径内容替换、网盘新增剧集、断网离线继承。只有实际在对应本地目录和网盘来源上操作并观察索引/播放结果后，才能将其标记为已验证。
