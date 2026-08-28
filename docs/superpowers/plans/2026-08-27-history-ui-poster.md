# 观看历史界面与海报修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化观看历史的单集时间线布局，并让缺图记录复用同来源、同剧集的有效海报。

**Architecture:** 保持现有 `HistoryPage`、`PlaybackHistoryController` 和海报组件边界。控制器在加载和写入历史时合并海报字段，页面只负责使用现有解析器生成简洁标题并保持 A 方案的 2:3 单行布局。

**Tech Stack:** Flutter 3.41.9、Dart、Material、现有 `LocalEpisodeParser`、Flutter Test。

---

## 文件职责

- `lib/features/history/domain/playback_history_entry.dart`：允许在不改变播放身份和进度的情况下复制海报字段。
- `lib/features/history/application/playback_history_controller.dart`：加载旧记录和写入新进度时补齐海报，不让空值覆盖有效值。
- `lib/pages/video/local_video_controller.dart`：当前集缺图时从同一播放列表选择有效海报写入历史。
- `lib/features/history/presentation/history_page.dart`：生成简洁标题，保留日期时间线和 `60 × 90` 海报排布。
- `test/playback_history_test.dart`：覆盖海报合并和标题显示回归。
- `test/cloud_playback_resolver_test.dart`：覆盖播放器写入历史前的播放列表海报兜底。

### Task 1: 观看历史海报合并

**Files:**
- Modify: `test/playback_history_test.dart`
- Modify: `lib/features/history/domain/playback_history_entry.dart`
- Modify: `lib/features/history/application/playback_history_controller.dart`
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写入两个失败测试**

先把 `_entry` 调整为：

```dart
PlaybackHistoryEntry _entry({
  String key = 'local|file:/media/a.mp4',
  String seriesTitle = '测试剧集',
  String episodeTitle = '第 1 集',
  int episodeIndex = 1,
  int position = 20,
  int duration = 100,
  String? posterUrl,
  String? posterCachePath,
}) {
  return PlaybackHistoryEntry(
    stableKey: key,
    source: key.startsWith('cloud|')
        ? PlaybackHistorySource.cloud
        : PlaybackHistorySource.local,
    sourceId: key.startsWith('cloud|') ? 'source-a' : 'local',
    seriesTitle: seriesTitle,
    episodeTitle: episodeTitle,
    mediaPath: key.startsWith('cloud|') ? '/anime/a.mp4' : '/media/a.mp4',
    remoteId: key.startsWith('cloud|') ? 'remote-a' : null,
    episodeIndex: episodeIndex,
    positionSeconds: position,
    durationSeconds: duration,
    updatedAt: DateTime(2026, 8, 5, 12),
    posterUrl: posterUrl,
    posterCachePath: posterCachePath,
  );
}
```

然后新增：

```dart
test('加载历史时为同来源同剧集的缺图记录复用有效海报', () async {
  final storage = MemoryPlaybackHistoryStorage(<Object?>[
    _entry(
      key: 'cloud|episode-22',
      seriesTitle: '古灵精探 S01',
      posterUrl: null,
    ).toJson(),
    _entry(
      key: 'cloud|episode-21',
      seriesTitle: '古灵精探 S01',
      posterUrl: '/poster.jpg',
    ).toJson(),
  ]);
  final controller = PlaybackHistoryController(
    repository: PlaybackHistoryRepository(storage: storage),
  );

  await controller.ensureLoaded();

  expect(controller.entries.first.posterUrl, '/poster.jpg');
  controller.dispose();
});

test('更新进度时空海报不会覆盖已有海报', () async {
  final controller = PlaybackHistoryController(
    repository: PlaybackHistoryRepository(
      storage: MemoryPlaybackHistoryStorage(),
    ),
  );
  await controller.record(
    _entry(position: 10, posterUrl: '/poster.jpg'),
    forcePersist: true,
  );

  await controller.record(_entry(position: 20), forcePersist: true);

  expect(controller.entries.single.posterUrl, '/poster.jpg');
  controller.dispose();
});
```

- [ ] **Step 2: 运行测试并确认 RED**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart --plain-name '加载历史时为同来源同剧集的缺图记录复用有效海报'
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart --plain-name '更新进度时空海报不会覆盖已有海报'
```

预期：两个测试均因实际 `posterUrl` 为 `null` 而失败，不是编译错误。

- [ ] **Step 3: 扩展记录复制字段**

在 `PlaybackHistoryEntry.copyWith` 增加海报参数，并传入构造函数：

```dart
PlaybackHistoryEntry copyWith({
  int? positionSeconds,
  int? durationSeconds,
  DateTime? updatedAt,
  String? posterUrl,
  String? posterCachePath,
}) {
  return PlaybackHistoryEntry(
    stableKey: stableKey,
    source: source,
    sourceId: sourceId,
    seriesTitle: seriesTitle,
    episodeTitle: episodeTitle,
    mediaPath: mediaPath,
    remoteId: remoteId,
    episodeIndex: episodeIndex,
    positionSeconds: positionSeconds ?? this.positionSeconds,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    updatedAt: updatedAt ?? this.updatedAt,
    posterUrl: posterUrl ?? this.posterUrl,
    posterCachePath: posterCachePath ?? this.posterCachePath,
  );
}
```

- [ ] **Step 4: 在控制器统一补齐海报**

`ensureLoaded` 读入后调用 `_backfillPosters()`；`record` 在替换前调用 `_withPosterFallback(entry)`。实现只匹配相同 `sourceId` 和去空格、小写后的 `seriesTitle`：

```dart
PlaybackHistoryEntry _withPosterFallback(PlaybackHistoryEntry entry) {
  final series = entry.seriesTitle.trim().toLowerCase();
  if (series.isEmpty) return entry;
  PlaybackHistoryEntry? fallback;
  for (final candidate in _entries) {
    if (candidate.sourceId == entry.sourceId &&
        candidate.seriesTitle.trim().toLowerCase() == series &&
        (candidate.posterUrl != null || candidate.posterCachePath != null)) {
      fallback = candidate;
      break;
    }
  }
  return entry.copyWith(
    posterUrl: entry.posterUrl ?? fallback?.posterUrl,
    posterCachePath: entry.posterCachePath ?? fallback?.posterCachePath,
  );
}

void _backfillPosters() {
  for (var index = 0; index < _entries.length; index++) {
    _entries[index] = _withPosterFallback(_entries[index]);
  }
}
```

- [ ] **Step 5: 写入同播放列表海报兜底失败测试**

在 `test/cloud_playback_resolver_test.dart` 新增：

```dart
test('观看历史从同一播放列表补齐当前集缺失的海报', () async {
  final controller = LocalVideoController(
    resolveCloudPlayback: (target) async => CloudResolvedPlayback(
      target: target,
      videoUrl: 'https://cdn.example.com${target.remotePath}',
      httpHeaders: const <String, String>{},
    ),
    initializePlayer: (_) async {},
  );
  await controller.openCloudPlayback(
    seriesTitle: '古灵精探 S01',
    targets: const <CloudPlaybackTarget>[
      CloudPlaybackTarget(
        sourceId: 'quark-home',
        remoteId: '22',
        remotePath: '/古灵精探 S01E22.mkv',
        stableId: '22',
        title: '古灵精探 S01E22.mkv',
      ),
      CloudPlaybackTarget(
        sourceId: 'quark-home',
        remoteId: '21',
        remotePath: '/古灵精探 S01E21.mkv',
        stableId: '21',
        title: '古灵精探 S01E21.mkv',
        posterUrl: '/poster.jpg',
        posterCachePath: r'D:\海报\古灵精探.jpg',
      ),
    ],
    selectedStableId: '22',
  );

  final entry = controller.buildPlaybackHistoryEntry(
    position: const Duration(minutes: 14),
    duration: const Duration(minutes: 43),
  );

  expect(entry?.posterUrl, '/poster.jpg');
  expect(entry?.posterCachePath, r'D:\海报\古灵精探.jpg');
});
```

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\cloud_playback_resolver_test.dart --plain-name '观看历史从同一播放列表补齐当前集缺失的海报'
```

预期：当前历史记录的两个海报字段为 `null`，测试失败。

- [ ] **Step 6: 在播放器历史入口复用同播放列表海报**

在 `LocalVideoController.buildPlaybackHistoryEntry` 的网盘分支查找第一个包含有效海报字段的目标，并分别作为空字段兜底：

```dart
CloudPlaybackTarget? posterFallback;
for (final candidate in cloudTargets) {
  if (candidate.posterUrl?.trim().isNotEmpty == true ||
      candidate.posterCachePath?.trim().isNotEmpty == true) {
    posterFallback = candidate;
    break;
  }
}
return PlaybackHistoryEntry(
  stableKey: _cloudHistoryKey(target),
  source: PlaybackHistorySource.cloud,
  sourceId: target.sourceId,
  seriesTitle: _cloudSeriesTitle ?? title,
  episodeTitle: target.title,
  mediaPath: target.remotePath,
  remoteId: target.remoteId,
  episodeIndex: currentEpisode,
  positionSeconds: _seconds(position),
  durationSeconds: _seconds(duration),
  updatedAt: DateTime.now(),
  posterUrl: target.posterUrl ?? posterFallback?.posterUrl,
  posterCachePath:
      target.posterCachePath ?? posterFallback?.posterCachePath,
);
```

- [ ] **Step 7: 运行海报测试并确认 GREEN**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart test\cloud_playback_resolver_test.dart
```

预期：两个测试文件全部通过。

### Task 2: A 方案标题与单行布局

**Files:**
- Modify: `test/playback_history_test.dart`
- Modify: `lib/features/history/presentation/history_page.dart`

- [ ] **Step 1: 写入标题失败测试**

导入 `history_page.dart`，新增：

```dart
test('观看历史标题隐藏扩展名并保留剧名集号和集名', () {
  final entry = _entry(
    seriesTitle: '古灵精探 S01',
    episodeTitle: '古灵精探 S01E22 儿子被绑 国富大惊.mkv',
    episodeIndex: 22,
  );

  expect(
    formatPlaybackHistoryTitle(entry),
    '古灵精探 S01 · 第22集 · 儿子被绑 国富大惊',
  );
});
```

- [ ] **Step 2: 运行标题测试并确认 RED**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart --plain-name '观看历史标题隐藏扩展名并保留剧名集号和集名'
```

预期：因 `formatPlaybackHistoryTitle` 尚不存在而编译失败；完成最小函数声明后再次运行，应因仍显示原文件名而断言失败。

- [ ] **Step 3: 复用现有解析器生成标题**

在 `history_page.dart` 导入 `LocalEpisodeParser` 和 `path`，新增：

```dart
final _historyEpisodeParser = LocalEpisodeParser();

String formatPlaybackHistoryTitle(PlaybackHistoryEntry entry) {
  final raw = entry.episodeTitle.trim().isEmpty
      ? entry.mediaPath
      : entry.episodeTitle;
  final parsed = _historyEpisodeParser.parse(raw);
  final rawName = p.basenameWithoutExtension(raw).trim();
  final episodeName = parsed == null
      ? rawName
      : (parsed.episodeTitle?.trim() ?? '');
  final parts = <String>[
    if (entry.seriesTitle.trim().isNotEmpty) entry.seriesTitle.trim(),
    '第${entry.episodeIndex}集',
    if (episodeName.isNotEmpty &&
        episodeName.toLowerCase() != entry.seriesTitle.trim().toLowerCase())
      episodeName,
  ];
  return parts.join(' · ');
}
```

将 `_HistoryTile.title` 的文本改为 `formatPlaybackHistoryTitle(entry)`；保留现有 `60 × 90` 海报、两行标题、来源/进度/观看时间、时长和进度条。

保持现有“继续观看 / 全部历史”筛选、“今天、昨天、更早”日期分组和删除按钮位置，不新增卡片墙或同剧归组。海报仍交给 `CloudPosterImage`、`PosterCover` 和 `TmdbNetworkImage`，不会由历史页主动发起额外补图请求。

- [ ] **Step 4: 运行相关测试并确认 GREEN**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart test\history_cloud_poster_contract_test.dart test\poster_cover_layout_contract_test.dart test\tmdb_image_network_contract_test.dart
```

预期：四个测试文件全部通过。

### Task 3: 全量验证与对抗式审查

**Files:**
- Verify only: 本轮相关文件和现有工作区状态

- [ ] **Step 1: 格式化本轮 Dart 文件**

运行：

```powershell
& 'D:\flutter\bin\dart.bat' format lib\features\history\domain\playback_history_entry.dart lib\features\history\application\playback_history_controller.dart lib\features\history\presentation\history_page.dart test\playback_history_test.dart
```

预期：只格式化本轮相关 Dart 文件。

- [ ] **Step 2: 运行完整测试**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test
```

预期：退出码为 0；若遇到已知的本地测试监听失败，按小批次串行复跑并明确记录未覆盖范围。

- [ ] **Step 3: 运行静态分析**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' analyze
```

预期：无 error。

- [ ] **Step 4: 构建 Windows Release**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' build windows --release
```

预期：退出码为 0，生成 `build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 5: 对抗式审查并检查差异**

运行：

```powershell
git diff --check
git status --short
git diff -- lib/features/history/domain/playback_history_entry.dart lib/features/history/application/playback_history_controller.dart lib/features/history/presentation/history_page.dart test/playback_history_test.dart
```

逐项确认：只匹配同来源同剧名；空剧名不串图；本地与网盘共用逻辑但不改变文件；删除和清空行为不变；没有修改 Android TV 发布流程；没有覆盖工作区原有无关改动；不执行 Git commit。
