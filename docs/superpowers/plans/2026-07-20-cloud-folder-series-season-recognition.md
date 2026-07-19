# 网盘文件夹剧名与季度识别 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让网盘扫描从“剧名加季度”或“剧名/季度”文件夹结构识别剧名和季号，并与纯集数文件名组合成可靠的剧集索引和 TMDB 搜索草稿。

**Architecture:** 新建无状态 `CloudMediaPathParser`，集中解析完整远程路径并复用 `LocalEpisodeParser` 的文件名结果。`CloudMediaIndexer`、`CloudSeriesIdentityResolver` 和网盘资源 TMDB 草稿统一消费解析结果；底层继续使用现有索引字段，不引入数据迁移。

**Tech Stack:** Dart 3、Flutter 3.41.9、Flutter Test、Flutter Modular、MobX、path、现有 TMDB 与网盘索引服务。

---

## 文件结构

- 新建 `lib/services/cloud/cloud_media_path_parser.dart`：只负责从完整远程路径解析剧名、季号、集号和冲突信息。
- 新建 `test/cloud_media_path_parser_test.dart`：覆盖目录格式、中文数字、优先级和分类目录保护。
- 修改 `lib/services/cloud/cloud_media_indexer.dart`：扫描和字幕关联使用统一路径结果，并记录季号冲突。
- 修改 `lib/services/cloud/cloud_series_identity_resolver.dart`：海报墙聚合和系列规则使用统一路径结果。
- 修改 `lib/services/cloud/cloud_media_name_parser.dart`：TMDB 名称清理兼容 `Season 2` 与中文数字季度。
- 修改 `lib/pages/cloud/resources/cloud_resources_controller.dart`：手动 TMDB 对话框从索引取得剧名、季号和集号。
- 修改对应测试文件：验证索引、聚合、TMDB 草稿及既有行为。
- 修改版本和发布文案：交付 `2.1.17`。

### Task 1: 建立网盘路径识别器

**Files:**
- Create: `lib/services/cloud/cloud_media_path_parser.dart`
- Create: `test/cloud_media_path_parser_test.dart`

- [ ] **Step 1: 写入单层和两层目录的失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_path_parser.dart';

void main() {
  final parser = CloudMediaPathParser();

  test('从剧名加季度文件夹和纯集数文件名组合剧集身份', () {
    final result = parser.parse('/电视剧/权力的游戏 第2季/03.mkv');

    expect(result.seriesName, '权力的游戏');
    expect(result.seasonNumber, 2);
    expect(result.episodeNumber, 3);
    expect(result.hasSeasonConflict, isFalse);
  });

  test('从纯季度文件夹和紧邻上级文件夹组合剧集身份', () {
    final result = parser.parse('/电视剧/权力的游戏/Season 2/EP03.mkv');

    expect(result.seriesName, '权力的游戏');
    expect(result.seasonNumber, 2);
    expect(result.episodeNumber, 3);
  });
}
```

- [ ] **Step 2: 运行测试并确认因类型不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_path_parser_test.dart`

Expected: FAIL，提示找不到 `cloud_media_path_parser.dart` 或 `CloudMediaPathParser`。

- [ ] **Step 3: 实现最小路径结果类型和目录解析入口**

```dart
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:path/path.dart' as p;

@immutable
class CloudMediaPathMatch {
  const CloudMediaPathMatch({
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.folderSeasonNumber,
    this.hasSeasonConflict = false,
  });

  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? folderSeasonNumber;
  final bool hasSeasonConflict;

  bool get isEpisode =>
      seriesName?.trim().isNotEmpty == true &&
      episodeNumber != null &&
      episodeNumber! > 0;
}

class CloudMediaPathParser {
  CloudMediaPathParser({LocalEpisodeParser? episodeParser})
      : _episodeParser = episodeParser ?? LocalEpisodeParser();

  final LocalEpisodeParser _episodeParser;

  CloudMediaPathMatch parse(String remotePath) {
    final normalizedPath = remotePath.trim().replaceAll('\\', '/');
    final fileName = p.posix.basenameWithoutExtension(normalizedPath);
    final parentName = p.posix.basename(p.posix.dirname(normalizedPath));
    final folder = _parseFolder(parentName, normalizedPath);
    final episode = _parseStandaloneEpisode(fileName);
    return CloudMediaPathMatch(
      seriesName: folder.$1,
      seasonNumber: folder.$2,
      episodeNumber: episode,
      folderSeasonNumber: folder.$2,
    );
  }

  (String?, int?) _parseFolder(String parentName, String remotePath) {
    final match = RegExp(
      r'^(.*?)(?:第\s*(\d{1,2})\s*季|season\s*(\d{1,2}))$',
      caseSensitive: false,
    ).firstMatch(parentName.trim());
    if (match == null) return (null, null);
    final season = int.tryParse(match.group(2) ?? match.group(3) ?? '');
    final inlineTitle = match.group(1)?.trim() ?? '';
    if (inlineTitle.isNotEmpty) return (inlineTitle, season);
    final grandParent = p.posix.basename(
      p.posix.dirname(p.posix.dirname(remotePath)),
    );
    return (grandParent.trim(), season);
  }

  int? _parseStandaloneEpisode(String value) {
    final match = RegExp(
      r'^(?:ep?|第)?\s*(\d{1,3})\s*(?:集)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
```

- [ ] **Step 4: 运行核心测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_path_parser_test.dart`

Expected: PASS，两条测试通过。

- [ ] **Step 5: 先补齐格式、冲突与分类目录的失败测试**

```dart
test('支持中文数字季度和 S02 季度后缀', () {
  expect(parser.parse('/剧集/三体 第二季/第1集.mkv').seasonNumber, 2);
  expect(parser.parse('/剧集/三体 S02/E01.mkv').seriesName, '三体');
});

test('文件名明确季号覆盖文件夹季号', () {
  final result = parser.parse('/剧集/三体 第2季/三体.S01E03.mkv');

  expect(result.seriesName, '三体');
  expect(result.seasonNumber, 1);
  expect(result.folderSeasonNumber, 2);
  expect(result.episodeNumber, 3);
  expect(result.hasSeasonConflict, isTrue);
});

test('普通分类目录不会被当成纯季度目录的剧名', () {
  final result = parser.parse('/电视剧/第2季/01.mkv');

  expect(result.seriesName, isNull);
  expect(result.seasonNumber, 2);
  expect(result.isEpisode, isFalse);
});

test('原有完整文件名识别保持不变', () {
  final result = parser.parse('/任意目录/Alice.in.Borderland.S01E03.mkv');

  expect(result.seriesName, 'Alice in Borderland');
  expect(result.seasonNumber, 1);
  expect(result.episodeNumber, 3);
});
```

- [ ] **Step 6: 运行新增测试并确认因格式和优先级未实现而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_path_parser_test.dart`

Expected: FAIL，中文数字季度、文件名优先级和分类目录保护断言不满足。

- [ ] **Step 7: 完成格式解析、中文数字和文件名优先级**

使用构造函数中的 `LocalEpisodeParser` 解析完整文件名；目录解析使用锚定到末尾的季度表达式。中文数字转换只接受 1 至 99：

```dart
static const Set<String> _genericDirectoryNames = <String>{
  '电视剧', '剧集', 'tv', 'shows', 'series', '动漫', 'anime',
  '媒体', 'media', '视频', 'video', '网盘', '夸克网盘', '已整理',
};

int? _parseChineseNumber(String value) {
  const digits = <String, int>{
    '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3,
    '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  if (!value.contains('十')) return digits[value];
  final parts = value.split('十');
  final tens = parts.first.isEmpty ? 1 : digits[parts.first];
  final ones = parts.length < 2 || parts.last.isEmpty ? 0 : digits[parts.last];
  if (tens == null || ones == null) return null;
  final result = tens * 10 + ones;
  return result >= 1 && result <= 99 ? result : null;
}
```

最终结果使用文件名显式季号覆盖目录季号，只有文件名没有剧集结果时才使用纯集数表达式。文件名结果的 `seriesName` 优先于目录剧名；纯集数文件使用目录剧名。

- [ ] **Step 8: 运行路径识别器测试并确认全部通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_path_parser_test.dart test\local_episode_parser_test.dart`

Expected: PASS。

- [ ] **Step 9: 提交路径识别器**

```powershell
git add -- lib/services/cloud/cloud_media_path_parser.dart test/cloud_media_path_parser_test.dart
git commit -m "识别网盘文件夹剧名和季度"
```

### Task 2: 将统一结果写入索引和系列身份

**Files:**
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Modify: `lib/services/cloud/cloud_series_identity_resolver.dart`
- Modify: `test/cloud_media_indexer_test.dart`
- Modify: `test/cloud_series_identity_resolver_test.dart`

- [ ] **Step 1: 写入索引和系列身份失败测试**

在 `test/cloud_media_indexer_test.dart` 添加递归目录用例：

```dart
test('从剧名和季度文件夹索引纯集数视频', () async {
  final repository =
      CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
  final client = _FakeCloudClient(<String, List<CloudFileEntry>>{
    '/动漫': <CloudFileEntry>[_dir('show', '/动漫/三体')],
    '/动漫/三体': <CloudFileEntry>[_dir('season', '/动漫/三体/第二季')],
    '/动漫/三体/第二季': <CloudFileEntry>[
      _file('episode', '/动漫/三体/第二季/01.mkv', size: _videoSize),
    ],
  });

  await CloudMediaIndexer(repository: repository).scan(
    source: source,
    client: client,
  );

  final item = (await repository.getBySource(source.id)).single;
  expect(item.seriesName, '三体');
  expect(item.seasonNumber, 2);
  expect(item.episodeNumber, 1);
  expect(item.mediaType, CloudMediaType.episode);
});
```

在 `test/cloud_series_identity_resolver_test.dart` 添加：

```dart
test('纯集数文件使用文件夹剧名和季度生成系列身份', () {
  final identity = CloudSeriesIdentityResolver().resolve(
    sourceId: 'quark',
    remotePath: '/剧集/三体 第二季/01.mkv',
    size: 200,
    minSizeBytes: 100,
  );

  expect(identity?.seriesName, '三体');
  expect(identity?.seasonNumber, 2);
  expect(identity?.episodeNumber, 1);
  expect(identity?.normalizedSeriesName, '三体');
});
```

- [ ] **Step 2: 运行测试并确认旧解析器无法识别纯集数文件**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart test\cloud_series_identity_resolver_test.dart`

Expected: FAIL，索引将 `01.mkv` 视为电影且 resolver 返回 `null`。

- [ ] **Step 3: 在索引器中注入并使用 `CloudMediaPathParser`**

构造函数新增可选依赖，扫描时只解析一次：

```dart
CloudMediaIndexer({
  required CloudMediaIndexRepository repository,
  CloudMediaPathParser? mediaPathParser,
  // 保留其他现有参数。
}) : _mediaPathParser = mediaPathParser ?? CloudMediaPathParser(),
     // 保留其他现有初始化。
;

final CloudMediaPathParser _mediaPathParser;
```

建立索引条目时改为：

```dart
final pathMatch = _mediaPathParser.parse(entry.remotePath);
if (pathMatch.hasSeasonConflict) {
  AppLogger().w(
    '网盘剧集季号冲突，采用文件名季号：${entry.remotePath} '
    '文件名=${pathMatch.seasonNumber} 文件夹=${pathMatch.folderSeasonNumber}',
  );
}
items[_normalizePath(entry.remotePath)] = CloudMediaIndexItem(
  sourceId: source.id,
  remoteId: entry.id,
  remotePath: _normalizePath(entry.remotePath),
  name: entry.name,
  size: entry.size,
  modifiedAt: entry.modifiedAt,
  seriesName: _seriesName(entry.name, pathMatch.seriesName),
  seasonNumber: pathMatch.seasonNumber,
  episodeNumber: pathMatch.episodeNumber,
  mediaType: _isSpecial(entry.remotePath)
      ? CloudMediaType.special
      : pathMatch.isEpisode
          ? CloudMediaType.episode
          : CloudMediaType.movie,
  subtitlePaths: subtitleRefs.map((reference) => reference.path).toList(),
  subtitleRefs: subtitleRefs,
);
```

字幕季集匹配也使用 `CloudMediaPathParser`，保持 `01.mkv` 与 `01.srt` 在相同季度目录内可关联。

- [ ] **Step 4: 在系列身份解析器中复用相同路径识别器**

```dart
CloudSeriesIdentityResolver({CloudMediaPathParser? mediaPathParser})
    : _mediaPathParser = mediaPathParser ?? CloudMediaPathParser();

final CloudMediaPathParser _mediaPathParser;

final episode = _mediaPathParser.parse(normalizedPath);
if (!episode.isEpisode || episode.episodeNumber == null) return null;
final seriesName = episode.seriesName!.trim();
final normalizedSeriesName = normalizeSeriesName(seriesName);
```

返回值继续使用现有 `parentPath`、`stableKey` 和安全边界。

- [ ] **Step 5: 运行索引、身份、字幕和海报墙测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart test\cloud_series_identity_resolver_test.dart test\cloud_resource_collection_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交索引集成**

```powershell
git add -- lib/services/cloud/cloud_media_indexer.dart lib/services/cloud/cloud_series_identity_resolver.dart test/cloud_media_indexer_test.dart test/cloud_series_identity_resolver_test.dart
git commit -m "使用文件夹结果索引网盘剧集"
```

### Task 3: 让手动和自动 TMDB 匹配使用索引剧名

**Files:**
- Modify: `lib/services/cloud/cloud_media_name_parser.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_media_name_parser_test.dart`
- Modify: `test/cloud_resource_tmdb_service_test.dart`
- Modify: `test/cloud_resource_tmdb_coordinator_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 写入 TMDB 名称和控制器草稿失败测试**

在 `test/cloud_media_name_parser_test.dart` 添加：

```dart
test('目录季度后缀不会进入 TMDB 搜索词', () {
  final draft = parser.parse(
    originalName: '三体 Season 2',
    isDirectory: true,
  );

  expect(draft.searchTitle, '三体');
  expect(draft.seasonNumber, 2);
  expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
});
```

在控制器测试中构造已索引的 `/动漫/三体/第二季/01.mkv`，选择来源并等待缓存加载后断言：

```dart
final draft = controller.tmdbDraftFor(controller.entries.single);
expect(draft.searchTitle, '三体');
expect(draft.seasonNumber, 2);
expect(draft.episodeNumber, 1);
expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);

final target = controller.tmdbTargetFor(controller.entries.single);
expect(target.matchingTitle, '三体');
expect(target.matchingSeasonNumber, 2);
expect(target.matchingEpisodeNumber, 1);
```

在 `test/cloud_resource_tmdb_service_test.dart` 增加目标 `displayName: '01.mkv'`、`matchingTitle: '三体'` 的搜索用例，断言 TMDB 客户端收到的查询词为 `三体`。在 coordinator 测试中向目录上下文传入同一条索引记录，断言自动调度也使用带 `matchingTitle` 的目标。

- [ ] **Step 2: 运行测试并确认搜索词或季集信息错误**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_name_parser_test.dart test\cloud_resources_controller_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_resource_tmdb_coordinator_test.dart`

Expected: FAIL，`Season 2` 未清理、目标类型没有索引匹配字段，或控制器仍从 `01.mkv` 生成草稿。

- [ ] **Step 3: 扩展 TMDB 目标而不改变真实显示名**

`CloudMediaNameParser` 增加 `Season 2`、`S02` 和中文数字季度后缀识别，并在 `_cleanTitle` 中移除同一个已识别季度表达式。

`CloudResourceTmdbTarget` 增加仅用于匹配的可空字段，`displayName` 继续保留真实网盘文件名：

```dart
const CloudResourceTmdbTarget({
  required this.sourceId,
  required this.remote,
  required this.displayName,
  required this.resourceKind,
  this.customTitle,
  this.matchingTitle,
  this.matchingSeasonNumber,
  this.matchingEpisodeNumber,
  this.size,
});

final String? matchingTitle;
final int? matchingSeasonNumber;
final int? matchingEpisodeNumber;

String? get effectiveMatchingTitle {
  final custom = customTitle?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final indexed = matchingTitle?.trim();
  return indexed == null || indexed.isEmpty ? null : indexed;
}
```

`CloudResourceTmdbService._requestFor` 将 `effectiveMatchingTitle` 作为 `preferredTitle`，因此自动刮削搜索 `三体`，但保存到记录中的 `displayName` 仍为 `01.mkv`。

- [ ] **Step 4: 从索引构造手动草稿和自动调度目标**

`CloudResourcesController.tmdbDraftFor` 先生成原草稿，再用 `_indexedItemFor(entry)` 覆盖可靠字段：

```dart
final record = tmdbRecordFor(entry);
final parsed = const CloudMediaNameParser().parse(
  originalName: entry.name,
  isDirectory: entry.isDirectory,
  preferredTitle: record?.customTitle ?? record?.title,
);
final indexed = _indexedItemFor(entry);
if (indexed == null || indexed.mediaType != CloudMediaType.episode) {
  return parsed;
}
return TmdbMatchDraft(
  originalName: parsed.originalName,
  searchTitle: record?.customTitle?.trim().isNotEmpty == true
      ? record!.customTitle!.trim()
      : indexed.seriesName,
  mediaTypeMode: TmdbMediaTypeMode.tv,
  year: parsed.year,
  seasonNumber: indexed.seasonNumber ?? parsed.seasonNumber,
  episodeNumber: indexed.episodeNumber ?? parsed.episodeNumber,
);
```

`tmdbTargetFor` 同样从 `_indexedItemFor(entry)` 填入三个 matching 字段。`CloudResourceDirectoryContext` 增加默认空的 `indexedItemsByKey`，控制器调度时传入 `_indexedItems` 的不可修改副本。Coordinator 用统一 `_targetForEntry` 方法为系列规则应用和自动调度构造目标：

```dart
CloudResourceTmdbTarget _targetForEntry(
  CloudResourceDirectoryContext context,
  CloudFileEntry entry,
  CloudResourceTmdbRecord? cached,
) {
  final key = cloudResourceTmdbKey(
    sourceId: context.source.id,
    remoteId: entry.id,
    remotePath: entry.remotePath,
  );
  final indexed = context.indexedItemsByKey[key];
  return CloudResourceTmdbTarget(
    sourceId: context.source.id,
    remote: CloudRemoteRef(id: entry.id, path: entry.remotePath),
    displayName: entry.name,
    resourceKind: entry.isDirectory
        ? CloudResourceKind.directory
        : CloudResourceKind.standaloneVideo,
    customTitle: cached?.customTitle,
    matchingTitle: indexed?.mediaType == CloudMediaType.episode
        ? indexed?.seriesName
        : null,
    matchingSeasonNumber: indexed?.seasonNumber,
    matchingEpisodeNumber: indexed?.episodeNumber,
    size: entry.isDirectory ? null : entry.size,
  );
}
```

- [ ] **Step 5: 运行 TMDB 与控制器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_name_parser_test.dart test\cloud_resources_controller_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_resource_tmdb_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交 TMDB 联动**

```powershell
git add -- lib/services/cloud/cloud_media_name_parser.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_media_name_parser_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m "使用网盘索引生成 TMDB 剧集草稿"
```

### Task 4: 更新版本和普通用户发布说明

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 先更新版本测试期望并确认失败**

将当前版本期望改为 `2.1.17`，新增更新弹窗断言：

```dart
test('二点一十七更新弹窗说明按文件夹识别剧名和季度', () {
  final current = versionHistoryList.first;
  expect(current.version, '2.1.17');
  expect(current.changes.join(), contains('文件夹'));
  expect(current.changes.join(), contains('季度'));
  expect(current.changes.join(), contains('文件名'));
});
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，当前版本仍为 `2.1.16`。

- [ ] **Step 2: 同步版本和发布文案**

- `pubspec.yaml`: `version: 2.1.17+20117`、`msix_version: 2.1.17.0`。
- `AppVersion.current`: `2.1.17`。
- `VersionHistory` 顶部增加 `2.1.17`，说明文件夹识别、文件名冲突优先级和不修改网盘文件。
- `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`README.md` 使用面向普通用户的同一能力描述。

- [ ] **Step 3: 运行版本测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 4: 提交发布信息**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "更新二点一十七发布信息"
```

### Task 5: 完整验证、Release、MSIX 和 Git 收尾

**Files:**
- Verify only: all modified source and test files
- Deliver: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `%USERPROFILE%\Desktop\看影音-2.1.17.msix`

- [ ] **Step 1: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: PASS，零失败。

- [ ] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`

- [ ] **Step 3: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `Built build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 4: 使用本机 DPAPI 密码生成签名 MSIX**

仅在封装期间将 `pubspec.yaml` 的 `sign_msix` 临时改为 `true`。读取 `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml` 为 `SecureString`，在当前 PowerShell 进程内转换后执行：

```powershell
D:\flutter\bin\dart.bat run msix:create --build-windows false --sign-msix true --certificate-path "$env:USERPROFILE\.kanyingyin\signing\certificate.pfx" --certificate-password $plainPassword
```

命令结束后清空明文变量、释放 BSTR，并将 `sign_msix` 恢复为 `false`。密码不得写盘或输出。

- [ ] **Step 5: 验证和复制安装包**

读取包内 `AppxManifest.xml` 并断言：

- Identity Name: `com.kanyingyin.player`
- Version: `2.1.17.0`
- Publisher: `CN=KanYingYin`
- ProcessorArchitecture: `x64`
- `AppxSignature.p7x` 存在
- `Get-AuthenticodeSignature` 状态为 `Valid`

复制为 `%USERPROFILE%\Desktop\看影音-2.1.17.msix`，比较源包与桌面包 SHA-256 完全相同。

- [ ] **Step 6: 审查并提交本轮遗漏文件**

Run: `git status --short` 和 `git diff --check`

只暂存本轮功能文件；保留 `.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md` 的用户修改。若没有遗漏源码则不创建空提交。

- [ ] **Step 7: 合并到本地 main 并复验**

```powershell
git checkout main
git merge --ff-only codex/cloud-folder-series-season-recognition
D:\flutter\bin\flutter.bat test --no-pub
git branch -d codex/cloud-folder-series-season-recognition
```

Expected: 快进合并成功、完整测试通过、功能分支安全删除；不推送远端。
