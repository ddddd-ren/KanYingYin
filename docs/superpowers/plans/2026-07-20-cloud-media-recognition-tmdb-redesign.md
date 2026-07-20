# 网盘媒体识别与 TMDB 季度海报重做 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将网盘媒体重构为“作品级识别与 TMDB 匹配、季度级海报卡、分集级播放”，并让用户界面显示不会改动远程文件的虚拟规范名称。

**Generality Rule:** 生产代码禁止包含任何示例作品名、固定 TMDB ID 或面向单一目录的分支；同一流程遍历每个已配置来源、每个媒体根和每个解析出的作品键。示例名称只允许出现在测试夹具和面向用户的说明中。

**Architecture:** 抽取本地与网盘共享的强类型名称分析器，再由网盘目录树解析器建立稳定的作品、季度和分集身份。索引保存原始名称、虚拟名称和作品边界；TMDB 记录改为作品级，一次详情请求向实际季度分配海报；资源页直接渲染季度卡，播放仍使用真实远程 ID 和路径。

**Tech Stack:** Dart 3、Flutter 3.41.9、Flutter Modular、MobX、Hive CE、Dio、path、Flutter Test、Windows MSIX。

---

## 文件结构

### 新建文件

- `lib/modules/media/media_name_analysis.dart`：共享名称分析结果、节点角色和发布规格类型。
- `lib/services/media_name_analyzer.dart`：解析作品、季度、分集、广告和发布规格，不处理目录树边界。
- `lib/modules/cloud/cloud_media_tree.dart`：网盘作品、季度、分集身份和值对象。
- `lib/services/cloud/cloud_media_tree_resolver.dart`：根据完整目录快照建立作品树并继承剧名、季号和集号。
- `lib/modules/cloud/cloud_work_tmdb_record.dart`：作品级 TMDB 状态、刮削名称覆盖和季度元数据。
- `lib/repositories/cloud_work_tmdb_repository.dart`：作品级 TMDB 记录持久化及来源级清理。
- `lib/services/cloud/cloud_work_tmdb_service.dart`：作品级搜索、选择、详情、海报缓存和索引同步。
- `lib/services/cloud/cloud_work_tmdb_coordinator.dart`：来源级自动刮削、手动确认、迁移和并发协调。
- `lib/pages/cloud/resources/cloud_media_details_dialog.dart`：只在详情中显示网盘原始名称和路径。
- 对应测试文件放在 `test/`，文件名与生产文件一致。

### 重点修改文件

- `lib/services/local_episode_parser.dart`：委托共享分析器提取季集和规格，保留本地电影误判保护。
- `lib/modules/cloud/cloud_media_index_item.dart`：增加作品键、作品根、原始名称、虚拟名称、规则版本和发布规格。
- `lib/repositories/cloud_media_index_repository.dart`：序列化新增字段并兼容旧索引。
- `lib/services/cloud/cloud_media_indexer.dart`：扫描后调用目录树解析器，按结构化身份写入索引。
- `lib/pages/cloud/resources/cloud_resource_collection.dart`：从“一剧一卡”改为“一季一卡”。
- `lib/pages/cloud/resources/cloud_resources_controller.dart`：读取作品级记录、生成虚拟条目并按作品执行 TMDB 操作。
- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：主海报墙直接使用季度海报。
- `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`：只显示当前季度和虚拟分集名。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：修改刮削名称、重新匹配和媒体详情入口。
- `lib/pages/cloud/resources/cloud_resources_module.dart` 与 `lib/app_module.dart`：注册新仓库与协调器。
- `lib/utils/storage.dart`：增加作品级 TMDB 存储键。
- 发布文件升级到 `2.1.18+20118 / 2.1.18.0`。

---

### Task 1: 建立共享名称分析类型与解析器

**Files:**
- Create: `lib/modules/media/media_name_analysis.dart`
- Create: `lib/services/media_name_analyzer.dart`
- Create: `test/media_name_analyzer_test.dart`

- [ ] **Step 1: 写季度、纯集号、广告和电影保护失败测试**

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/media_name_analyzer.dart';

void main() {
  const analyzer = MediaNameAnalyzer();

  test('带发布规格的季度目录不产生剧名', () {
    final first = analyzer.analyze(
      '第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos',
      isDirectory: true,
    );
    final second = analyzer.analyze(
      '第三季（2025）4K DV&HDR',
      isDirectory: true,
    );

    expect(first.role, MediaNodeRole.season);
    expect(first.seasonNumber, 3);
    expect(first.titleCandidates, isEmpty);
    expect(first.releaseTags.resolution, '2160p');
    expect(first.releaseTags.source, 'Web-DL');
    expect(first.releaseTags.codec, 'H265');
    expect(first.releaseTags.audio, contains('Atmos'));
    expect(second.seasonNumber, 3);
    expect(second.year, 2025);
    expect(second.releaseTags.dynamicRange, containsAll(<String>['DV', 'HDR']));
  });

  test('纯数字视频只输出集号证据', () {
    final result = analyzer.analyze('006.mkv', isDirectory: false);
    expect(result.role, MediaNodeRole.episode);
    expect(result.episodeNumber, 6);
    expect(result.titleCandidates, isEmpty);
  });

  test('广告和电影数字不会成为分集', () {
    expect(
      analyzer.analyze('0001更多资源请访问 00t.vip', isDirectory: true).role,
      MediaNodeRole.advertisement,
    );
    expect(
      analyzer.analyze('流浪地球2 2023 4K.mkv', isDirectory: false).role,
      isNot(MediaNodeRole.episode),
    );
  });

  test('有效剪辑版本不会被当成广告或普通重复项', () {
    final result = analyzer.analyze(
      '假面骑士OOO 第47-48集（导演剪辑版）.mkv',
      isDirectory: false,
    );
    expect(result.role, MediaNodeRole.version);
    expect(result.evidence, contains('director-cut'));
  });

  test('合法数字作品标题不会按季度编号删除', () {
    for (final title in <String>['The 100', '1923', '86 -不存在战区-']) {
      final result = analyzer.analyze(title, isDirectory: true);
      expect(result.titleCandidates, contains(title), reason: title);
    }
  });
}
~~~

- [ ] **Step 2: 运行测试并确认类型尚不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\media_name_analyzer_test.dart`

Expected: FAIL，提示找不到 `media_name_analysis.dart` 和 `MediaNameAnalyzer`。

- [ ] **Step 3: 实现强类型分析结果**

~~~dart
import 'package:flutter/foundation.dart';

enum MediaNodeRole { work, season, episode, version, advertisement, unknown }

@immutable
class MediaReleaseTags {
  const MediaReleaseTags({
    this.resolution,
    this.source,
    this.codec,
    this.dynamicRange = const <String>[],
    this.audio = const <String>[],
    this.releaseGroup,
  });

  final String? resolution;
  final String? source;
  final String? codec;
  final List<String> dynamicRange;
  final List<String> audio;
  final String? releaseGroup;

  Map<String, Object?> toJson() => <String, Object?>{
        if (resolution != null) 'resolution': resolution,
        if (source != null) 'source': source,
        if (codec != null) 'codec': codec,
        if (dynamicRange.isNotEmpty) 'dynamicRange': dynamicRange,
        if (audio.isNotEmpty) 'audio': audio,
        if (releaseGroup != null) 'releaseGroup': releaseGroup,
      };

  factory MediaReleaseTags.fromJson(Map<String, Object?> json) {
    return MediaReleaseTags(
      resolution: json['resolution'] as String?,
      source: json['source'] as String?,
      codec: json['codec'] as String?,
      dynamicRange: json['dynamicRange'] is List
          ? (json['dynamicRange'] as List).whereType<String>().toList()
          : const <String>[],
      audio: json['audio'] is List
          ? (json['audio'] as List).whereType<String>().toList()
          : const <String>[],
      releaseGroup: json['releaseGroup'] as String?,
    );
  }
}

@immutable
class MediaNameAnalysis {
  const MediaNameAnalysis({
    required this.originalName,
    required this.role,
    this.titleCandidates = const <String>[],
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.releaseTags = const MediaReleaseTags(),
    this.confidence = 0,
    this.evidence = const <String>[],
  });

  final String originalName;
  final MediaNodeRole role;
  final List<String> titleCandidates;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final MediaReleaseTags releaseTags;
  final double confidence;
  final List<String> evidence;
}
~~~

- [ ] **Step 4: 实现节点角色、季集和发布规格解析**

在 `lib/services/media_name_analyzer.dart` 中建立单一解析入口。季度表达式不锚定名称末尾；完成季度角色判断后，不把剩余规格回退成标题。

~~~dart
class MediaNameAnalyzer {
  const MediaNameAnalyzer();

  static final RegExp _season = RegExp(
    r'(?:第\s*([零〇一二两三四五六七八九十\d]{1,3})\s*季|\bSeason\s*(\d{1,2})\b|\bS(\d{1,2})(?!E\d))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _episode = RegExp(
    r'(?:\bS(\d{1,2})E(\d{1,3})\b|^(?:EP?|Episode)?\s*(\d{1,3})\s*$|^第\s*(\d{1,3})\s*集$)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _advertisement = RegExp(
    r'更多.*(?:资源|访问)|全网搜索|防走失|神秘入口|请访问|www\.|https?://|\.(?:vip|com|net)$',
    caseSensitive: false,
    unicode: true,
  );

  MediaNameAnalysis analyze(String name, {required bool isDirectory}) {
    final base = isDirectory
        ? name.trim()
        : name.replaceFirst(RegExp(r'\.[^.\\/]+$'), '').trim();
    if (_advertisement.hasMatch(base)) {
      return MediaNameAnalysis(
        originalName: name,
        role: MediaNodeRole.advertisement,
        confidence: 1,
        evidence: const <String>['advertisement-token'],
      );
    }
    final seasonMatch = _season.firstMatch(base);
    final episodeMatch = _episode.firstMatch(base);
    final seasonNumber = _seasonNumber(seasonMatch);
    final episodeNumber = _episodeNumber(episodeMatch);
    final role = episodeNumber != null
        ? MediaNodeRole.episode
        : seasonNumber != null
            ? MediaNodeRole.season
            : MediaNodeRole.unknown;
    return MediaNameAnalysis(
      originalName: name,
      role: role,
      titleCandidates: _titleCandidates(base, role),
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      year: _year(base),
      releaseTags: _releaseTags(base),
      confidence: role == MediaNodeRole.unknown ? 0.4 : 0.9,
      evidence: <String>[
        if (seasonNumber != null) 'season-token',
        if (episodeNumber != null) 'episode-token',
      ],
    );
  }
}
~~~

同文件实现 `_seasonNumber`、`_episodeNumber`、`_titleCandidates`、`_year` 和 `_releaseTags`。中文数字接受 1 至 99；规格词覆盖设计中的分辨率、片源、编码、DV/HDR、DDP/EAC3/Atmos 和声道。

~~~dart
int? _seasonNumber(RegExpMatch? match) {
  if (match == null) return null;
  return _parseNumber(match.group(1) ?? match.group(2) ?? match.group(3) ?? '');
}

int? _episodeNumber(RegExpMatch? match) {
  if (match == null) return null;
  return int.tryParse(
    match.group(2) ?? match.group(3) ?? match.group(4) ?? '',
  );
}

int? _year(String value) {
  final match = RegExp(r'(?:^|[\s（(])((?:19|20)\d{2})(?=$|[\s）)])')
      .firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}

MediaReleaseTags _releaseTags(String value) {
  String? first(RegExp pattern) => pattern.firstMatch(value)?.group(0);
  final dynamicRange = <String>[
    if (RegExp(r'\b(?:DV|Dolby\s*Vision)\b', caseSensitive: false)
        .hasMatch(value))
      'DV',
    if (RegExp(r'\bHDR(?:10\+?)?\b', caseSensitive: false).hasMatch(value))
      'HDR',
  ];
  final audio = <String>[
    if (RegExp(r'\b(?:DDP|EAC3)(?:\s*5\.1)?\b', caseSensitive: false)
        .hasMatch(value))
      'DDP 5.1',
    if (RegExp(r'\bAtmos\b', caseSensitive: false).hasMatch(value)) 'Atmos',
  ];
  return MediaReleaseTags(
    resolution: first(RegExp(
      r'\b(?:480p|720p|1080p|1440p|2160p|4K|8K)\b',
      caseSensitive: false,
    )),
    source: first(RegExp(
      r'\b(?:WEB-DL|WEBRip|BDRip|BluRay|HDTV|TVRip)\b',
      caseSensitive: false,
    )),
    codec: first(RegExp(
      r'\b(?:x264|x265|H264|H265|HEVC|AVC|AV1)\b',
      caseSensitive: false,
    )),
    dynamicRange: dynamicRange,
    audio: audio,
  );
}
~~~

`_titleCandidates` 先移除季集表达式、年份括号、发布规格、分享编号、全集说明和推广文本，再规范化分隔符；当角色是纯季度或纯集号且清理后只剩规格时返回空列表。`_parseNumber` 复用现有 `CloudMediaPathParser` 的中文数字 1 至 99 算法，迁移后只保留共享实现。

- [ ] **Step 5: 运行共享解析测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\media_name_analyzer_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交共享分析器**

~~~powershell
git add -- lib/modules/media/media_name_analysis.dart lib/services/media_name_analyzer.dart test/media_name_analyzer_test.dart
git commit -m "建立共享媒体名称分析器"
~~~

### Task 2: 让本地分集解析复用共享规则并保持兼容

**Files:**
- Modify: `lib/services/local_episode_parser.dart`
- Modify: `lib/modules/local/local_episode_info.dart`
- Modify: `test/local_episode_parser_test.dart`
- Modify: `test/local_media_indexer_test.dart`

- [ ] **Step 1: 增加本地发布规格和既有误判回归测试**

~~~dart
test('LocalEpisodeParser 复用共享动态范围和音轨清理', () {
  final info = parser.parse(
    'Alice in Borderland S03E01 2160p WEB-DL H265 DV HDR DDP 5.1 Atmos.mkv',
  );
  expect(info?.seriesName, 'Alice in Borderland');
  expect(info?.seasonNumber, 3);
  expect(info?.episodeNumber, 1);
  expect(info?.episodeTitle, isNull);
});

test('LocalEpisodeParser 继续保护年份和 4K 电影名', () {
  expect(parser.parse('流浪地球2 2023 4K.mkv'), isNull);
  expect(parser.parse('interstellar 2014 imax 4K-kc.mkv'), isNull);
});
~~~

- [ ] **Step 2: 运行本地解析测试并确认新规格残留导致失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_episode_parser_test.dart`

Expected: FAIL，新用例的 `episodeTitle` 仍包含 DV、HDR、DDP 或 Atmos。

- [ ] **Step 3: 注入 MediaNameAnalyzer 并统一规格清理**

~~~dart
LocalEpisodeParser({MediaNameAnalyzer? nameAnalyzer})
    : _nameAnalyzer = nameAnalyzer ?? const MediaNameAnalyzer();

final MediaNameAnalyzer _nameAnalyzer;

LocalEpisodeInfo? parse(String filePath) {
  final shared = _nameAnalyzer.analyze(
    p.basename(filePath),
    isDirectory: false,
  );
  final parsed = _parseWithExistingPatterns(filePath, shared);
  if (parsed == null) return null;
  return parsed.copyWith(
    episodeTitle: _cleanEpisodeTitle(
      parsed.episodeTitle ?? '',
      shared.releaseTags,
    ),
  );
}
~~~

把当前 `parse` 的模式循环原样移动到 `_parseWithExistingPatterns`，其返回类型仍为 `LocalEpisodeInfo?`。为 `LocalEpisodeInfo` 增加以下方法；`_cleanEpisodeTitle` 接收 `MediaReleaseTags` 并移除已识别规格。保留 `_shouldSkipBareEpisode`、`_looksLikeMovieLikeTitle` 和发布组目录回退。

~~~dart
LocalEpisodeInfo copyWith({String? episodeTitle, bool clearEpisodeTitle = false}) {
  return LocalEpisodeInfo(
    seriesName: seriesName,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    episodeTitle: clearEpisodeTitle ? null : episodeTitle ?? this.episodeTitle,
    releaseGroup: releaseGroup,
    resolution: resolution,
    source: source,
    codec: codec,
  );
}
~~~

- [ ] **Step 4: 运行本地解析与索引测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_episode_parser_test.dart test\local_media_indexer_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交本地解析复用**

~~~powershell
git add -- lib/services/local_episode_parser.dart lib/modules/local/local_episode_info.dart test/local_episode_parser_test.dart test/local_media_indexer_test.dart
git commit -m "统一本地媒体名称识别规则"
~~~

### Task 3: 建立网盘作品树和值对象

**Files:**
- Create: `lib/modules/cloud/cloud_media_tree.dart`
- Create: `lib/services/cloud/cloud_media_tree_resolver.dart`
- Create: `test/cloud_media_tree_resolver_test.dart`

- [ ] **Step 1: 用真实目录写作品树失败测试**

测试夹具包含第一季、第二季、两个第三季目录、01 至 06 纯数字视频、英文完整分集、广告目录和推广图片。

~~~dart
const resolver = CloudMediaTreeResolver();
final tree = resolver.resolve(
  sourceId: 'quark-a',
  configuredRoots: const <String>['/影视'],
  directoryEntries: fixture.directoryEntries,
  minSizeBytes: 100,
);

expect(tree.works, hasLength(1));
final work = tree.works.single;
expect(work.displayTitle, '弥留之国的爱丽丝');
expect(work.titleCandidates, containsAll(<String>[
  '弥留之国的爱丽丝',
  '弥留之国的爱丽丝3',
  'Alice in Borderland',
]));
expect(work.seasons.map((season) => season.seasonNumber), <int>[1, 2, 3]);
expect(work.seasons.last.remoteDirectories, hasLength(2));
expect(
  work.seasons.last.episodes.map((episode) => episode.episodeNumber),
  <int>[1, 2, 3, 4, 5, 6],
);
expect(tree.ignored.map((entry) => entry.name), contains('更多【神秘入口】.png'));
~~~

同一测试文件再构造包含“葬送的芙莉莲”“The 100”“1923”、独立电影和两个不同根同名作品的快照：

~~~dart
final matrix = resolver.resolve(
  sourceId: 'quark-a',
  configuredRoots: const <String>['/剧集', '/电影'],
  directoryEntries: multiWorkFixture.directoryEntries,
  minSizeBytes: 100,
);
expect(matrix.works.map((work) => work.displayTitle), containsAll(<String>[
  '葬送的芙莉莲',
  'The 100',
  '1923',
  '流浪地球2',
]));
expect(
  matrix.works.where((work) => work.displayTitle == '同名作品').map((work) => work.workKey).toSet(),
  hasLength(2),
);
~~~

- [ ] **Step 2: 运行测试并确认作品树类型不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_tree_resolver_test.dart`

Expected: FAIL，提示 `CloudMediaTreeResolver` 不存在。

- [ ] **Step 3: 实现不可变作品、季度和分集身份**

~~~dart
@immutable
class CloudEpisodeIdentity {
  const CloudEpisodeIdentity({
    required this.entry,
    required this.remoteName,
    required this.displayName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.releaseTags,
  });
  final CloudFileEntry entry;
  final String remoteName;
  final String displayName;
  final int seasonNumber;
  final int episodeNumber;
  final MediaReleaseTags releaseTags;
}

@immutable
class CloudSeasonIdentity {
  const CloudSeasonIdentity({
    required this.workKey,
    required this.seasonNumber,
    required this.displayName,
    required this.remoteDirectories,
    required this.episodes,
    this.year,
  });
  final String workKey;
  final int seasonNumber;
  final String displayName;
  final List<CloudFileEntry> remoteDirectories;
  final List<CloudEpisodeIdentity> episodes;
  final int? year;
}

@immutable
class CloudWorkIdentity {
  const CloudWorkIdentity({
    required this.sourceId,
    required this.workKey,
    required this.root,
    required this.remoteName,
    required this.displayTitle,
    required this.titleCandidates,
    required this.seasons,
    this.standaloneVideos = const <CloudFileEntry>[],
  });
  final String sourceId;
  final String workKey;
  final CloudFileEntry root;
  final String remoteName;
  final String displayTitle;
  final List<String> titleCandidates;
  final List<CloudSeasonIdentity> seasons;
  final List<CloudFileEntry> standaloneVideos;
}
~~~

- [ ] **Step 4: 实现目录树边界和上下文继承**

`CloudMediaTreeResolver.resolve` 按以下顺序执行：

1. 分析所有目录名和视频名。
2. 找到含有效季度子目录及有效视频后代的作品根。
3. 过滤分类目录与明确广告节点。
4. 作品根生成标题候选，分集文件标题只作为别名。
5. 季度目录提供季号，纯集号文件只在季度目录内有效。
6. 相同作品根和季号合并；不同作品根永不合并。
7. 冲突季号写入 `conflicts`，不覆盖远程数据。
8. 没有季度结构的合格视频写入 `standaloneVideos`，继续作为电影候选进入海报墙。
9. 对 `directoryEntries` 中每个候选作品根执行相同算法；解析器不得比较任何固定作品标题或 TMDB ID。

作品键使用来源和远程根 ID：

~~~dart
String workKeyFor(String sourceId, CloudFileEntry root) {
  final stableRoot = root.id.trim().isEmpty
      ? CloudSeriesIdentityResolver.normalizeRemotePath(root.remotePath)
      : root.id.trim();
  return '$sourceId|work|$stableRoot';
}
~~~

- [ ] **Step 5: 运行作品树测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_tree_resolver_test.dart test\media_name_analyzer_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交作品树**

~~~powershell
git add -- lib/modules/cloud/cloud_media_tree.dart lib/services/cloud/cloud_media_tree_resolver.dart test/cloud_media_tree_resolver_test.dart
git commit -m "建立网盘作品季度分集树"
~~~

### Task 4: 扩展网盘索引并强制重算旧派生字段

**Files:**
- Modify: `lib/modules/cloud/cloud_media_index_item.dart`
- Modify: `lib/repositories/cloud_media_index_repository.dart`
- Modify: `test/cloud_media_index_repository_test.dart`

- [ ] **Step 1: 写新增字段 JSON 往返和旧索引兼容测试**

~~~dart
test('索引往返保留作品边界原名虚拟名和规则版本', () async {
  final item = CloudMediaIndexItem(
    sourceId: 'quark-a',
    remoteId: 'episode-1',
    remotePath: '/影视/作品/第三季/01.mkv',
    name: '01.mkv',
    remoteName: '01.mkv',
    displayName: '弥留之国的爱丽丝 S03E01.mkv',
    workKey: 'quark-a|work|work-id',
    workRootId: 'work-id',
    workRootPath: '/影视/作品',
    size: 200,
    modifiedAt: null,
    seriesName: '弥留之国的爱丽丝',
    seasonNumber: 3,
    episodeNumber: 1,
    mediaType: CloudMediaType.episode,
    recognitionVersion: CloudMediaIndexItem.currentRecognitionVersion,
  );

  await repository.replaceSource(
    'quark-a',
    <CloudMediaIndexItem>[item],
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    const <String>['/影视'],
  );
  final restored = (await repository.getBySource('quark-a')).single;
  expect(restored.remoteName, '01.mkv');
  expect(restored.displayName, contains('S03E01'));
  expect(restored.workKey, 'quark-a|work|work-id');
  expect(restored.needsRecognitionRefresh, isFalse);
});
~~~

- [ ] **Step 2: 运行仓库测试并确认构造参数不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_index_repository_test.dart`

Expected: FAIL，提示 `remoteName`、`displayName`、`workKey` 或 `recognitionVersion` 未定义。

- [ ] **Step 3: 增加索引字段与兼容默认值**

~~~dart
class CloudMediaIndexItem {
  static const int currentRecognitionVersion = 2;

  final String remoteName;
  final String displayName;
  final String? workKey;
  final String? workRootId;
  final String? workRootPath;
  final int recognitionVersion;
  final MediaReleaseTags releaseTags;

  bool get needsRecognitionRefresh =>
      recognitionVersion < currentRecognitionVersion ||
      remoteName.isEmpty ||
      displayName.isEmpty ||
      (mediaType == CloudMediaType.episode && workKey == null);

  CloudMediaIndexItem withEffectiveWorkTitle(String title) {
    final extension = p.extension(remoteName);
    final season = seasonNumber;
    final episode = episodeNumber;
    final virtualName = season != null && episode != null
        ? '$title S${season.toString().padLeft(2, '0')}'
            'E${episode.toString().padLeft(2, '0')}$extension'
        : displayName;
    return copyWith(displayName: virtualName, seriesName: title);
  }
}
~~~

旧 JSON 缺少字段时使用：

~~~dart
remoteName: json['remoteName'] as String? ?? requiredString('name'),
displayName: json['displayName'] as String? ?? requiredString('name'),
recognitionVersion:
    json['recognitionVersion'] is int ? json['recognitionVersion'] as int : 0,
~~~

`copyWith` 增加可选 `displayName` 和 `seriesName`，并与 `replaceTmdb` 一样逐项传递全部结构字段，不能在更新 TMDB 时丢失 `workKey` 或虚拟名称。

- [ ] **Step 4: 运行索引仓库测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_index_repository_test.dart test\cloud_media_index_tmdb_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交索引模型**

~~~powershell
git add -- lib/modules/cloud/cloud_media_index_item.dart lib/repositories/cloud_media_index_repository.dart test/cloud_media_index_repository_test.dart test/cloud_media_index_tmdb_test.dart
git commit -m "扩展网盘作品身份索引"
~~~

### Task 5: 将作品树写入网盘索引

**Files:**
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Modify: `test/cloud_media_indexer_test.dart`
- Modify: `test/cloud_media_path_parser_test.dart`

- [ ] **Step 1: 增加真实目录扫描和旧指纹重算失败测试**

~~~dart
test('扫描真实多季度目录写入虚拟名称和统一作品键', () async {
  final result = await indexer.scan(source: source, client: fixture.client);
  final items = await repository.getBySource(source.id);

  expect(result.videoCount, greaterThanOrEqualTo(6));
  expect(items.map((item) => item.workKey).toSet(), hasLength(1));
  expect(items.map((item) => item.seasonNumber).toSet(), <int>{1, 2, 3});
  expect(
    items.where((item) => item.seasonNumber == 3).map((item) => item.displayName),
    contains('弥留之国的爱丽丝 S03E01.mkv'),
  );
  expect(items.every((item) => item.remoteName == item.name), isTrue);
});
~~~

另加 `recognitionVersion: 0` 的旧快照，断言远程指纹不变时仍重新生成 `workKey` 和 `displayName`。

- [ ] **Step 2: 运行索引器测试并确认仍使用单路径解析**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart`

Expected: FAIL，作品键和虚拟名称为空。

- [ ] **Step 3: 在完整目录扫描后调用 CloudMediaTreeResolver**

~~~dart
final tree = _mediaTreeResolver.resolve(
  sourceId: source.id,
  configuredRoots: roots,
  directoryEntries: directoryEntries,
  minSizeBytes: minSizeBytes,
);
final identitiesByPath = <String, CloudEpisodeIdentity>{
  for (final work in tree.works)
    for (final season in work.seasons)
      for (final episode in season.episodes)
        _normalizePath(episode.entry.remotePath): episode,
};
~~~

构造 `CloudMediaIndexItem` 时从 episode identity 写入 `remoteName`、`displayName`、`workKey`、`workRootId`、`workRootPath`、季集号和发布规格。字幕匹配仍使用真实 `remotePath` 和 `remoteName`。

- [ ] **Step 4: 将识别版本纳入跳过判定**

~~~dart
final recognitionStale =
    previous.items.any((item) => item.needsRecognitionRefresh);
var changed = recognitionStale ||
    previous.directoryEntries.isEmpty ||
    !_sameStringSet(previous.indexedRoots, roots) ||
    hasCachedPathsOutsideRoots;
~~~

不得因目录指纹相同提前返回旧派生字段。

- [ ] **Step 5: 运行索引、字幕和路径回归**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart test\cloud_media_path_parser_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交索引集成**

~~~powershell
git add -- lib/services/cloud/cloud_media_indexer.dart test/cloud_media_indexer_test.dart test/cloud_media_path_parser_test.dart
git commit -m "使用作品树索引网盘媒体"
~~~

### Task 6: 建立作品级 TMDB 记录与仓库

**Files:**
- Create: `lib/modules/cloud/cloud_work_tmdb_record.dart`
- Create: `lib/repositories/cloud_work_tmdb_repository.dart`
- Create: `test/cloud_work_tmdb_record_test.dart`
- Create: `test/cloud_work_tmdb_repository_test.dart`
- Modify: `lib/utils/storage.dart`

- [ ] **Step 1: 写作品记录序列化和来源隔离失败测试**

~~~dart
test('作品记录往返保留刮削名称和季度海报', () {
  final metadataWithThreeSeasons = TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.tv,
    title: '弥留之国的爱丽丝',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 7, 20),
    matchConfidence: 1,
    seasons: <TmdbSeasonMetadata>[
      for (var season = 1; season <= 3; season++)
        TmdbSeasonMetadata(
          id: season * 100,
          seasonNumber: season,
          name: '第 $season 季',
          episodeCount: season == 3 ? 6 : 8,
          posterUrl: '/season-$season.jpg',
        ),
    ],
  );
  final record = CloudWorkTmdbRecord.matched(
    sourceId: 'quark-a',
    workKey: 'quark-a|work|root-id',
    workRootId: 'root-id',
    workRootPath: '/影视/作品',
    remoteName: '154332_《弥留之国的爱丽丝3》',
    scrapeTitleOverride: '弥留之国的爱丽丝',
    metadata: metadataWithThreeSeasons,
    checkedAt: DateTime.utc(2026, 7, 20),
  );
  final restored = CloudWorkTmdbRecord.fromJson(record.toJson());
  expect(restored, record);
  expect(restored.seasons.map((item) => item.seasonNumber), <int>[1, 2, 3]);
});
~~~

- [ ] **Step 2: 运行新测试并确认类型不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_record_test.dart test\cloud_work_tmdb_repository_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现作品状态和有效显示标题**

~~~dart
enum CloudWorkTmdbStatus { unchecked, matched, unmatched, failed, conflict }

class CloudWorkTmdbRecord {
  final String sourceId;
  final String workKey;
  final String workRootId;
  final String workRootPath;
  final String remoteName;
  final String? scrapeTitleOverride;
  final CloudWorkTmdbStatus status;
  final TmdbMetadata? metadata;
  final DateTime checkedAt;

  String effectiveTitle(String recognizedTitle) {
    final tmdbTitle = metadata?.title.trim();
    if (status == CloudWorkTmdbStatus.matched &&
        tmdbTitle != null &&
        tmdbTitle.isNotEmpty) {
      return tmdbTitle;
    }
    final override = scrapeTitleOverride?.trim();
    return override == null || override.isEmpty ? recognizedTitle : override;
  }

  List<TmdbSeasonMetadata> get seasons =>
      metadata?.seasons ?? const <TmdbSeasonMetadata>[];
}
~~~

实现 `matched`、`unchecked`、`unmatched`、`failed`、`conflict` 工厂以及完整 JSON、相等性和 `copyWithScrapeTitle`。

- [ ] **Step 4: 实现仓库和新设置键**

在 `SettingBoxKey` 增加 `cloudWorkTmdbRecords`。仓库提供 `getBySource`、`get`、`upsert`、`upsertAll`、`replaceSource` 和 `removeSource`，并使用 `synchronized` 锁保护同一 Hive 设置盒。

~~~dart
abstract interface class CloudWorkTmdbStorage {
  Object get synchronizationIdentity;
  Future<List<Map<String, Object?>>> read();
  Future<void> write(List<Map<String, Object?>> records);
}
~~~

- [ ] **Step 5: 运行记录和仓库测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_record_test.dart test\cloud_work_tmdb_repository_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交作品记录**

~~~powershell
git add -- lib/modules/cloud/cloud_work_tmdb_record.dart lib/repositories/cloud_work_tmdb_repository.dart lib/utils/storage.dart test/cloud_work_tmdb_record_test.dart test/cloud_work_tmdb_repository_test.dart
git commit -m "建立作品级网盘 TMDB 记录"
~~~

### Task 7: 实现作品级 TMDB 详情与季度海报缓存

**Files:**
- Create: `lib/services/cloud/cloud_work_tmdb_service.dart`
- Create: `test/cloud_work_tmdb_service_test.dart`
- Modify: `lib/services/cloud/cloud_poster_cache.dart`

- [ ] **Step 1: 写一次详情请求和三季海报缓存失败测试**

~~~dart
test('一个作品只请求一次详情并缓存实际三季海报', () async {
  final outcome = await service.select(
    work,
    candidate,
    existingSeasons: const <int>{1, 2, 3},
    options: const TmdbScrapeOptions.defaults(),
  );

  expect(client.detailCalls, 1);
  expect(cache.stableIds, <String>[
    work.workKey,
    '${work.workKey}|season:1',
    '${work.workKey}|season:2',
    '${work.workKey}|season:3',
  ]);
  expect(outcome.record.seasons, hasLength(3));
  expect(outcome.updatedIndexItems, greaterThan(0));
});
~~~

- [ ] **Step 2: 运行测试并确认服务不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_service_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现作品搜索请求**

~~~dart
CloudResourceTmdbSearchRequest requestFor(
  CloudWorkIdentity work,
  CloudWorkTmdbRecord? record,
  TmdbScrapeOptions options,
) {
  final override = record?.scrapeTitleOverride?.trim();
  final query = override != null && override.isNotEmpty
      ? override
      : work.titleCandidates.first;
  return CloudResourceTmdbSearchRequest(
    queryTitle: query,
    queryYear: null,
    mediaTypeMode: work.seasons.isEmpty
        ? options.mediaTypeMode
        : TmdbMediaTypeMode.tv,
    options: options,
  );
}
~~~

多季度合集目录年份不能作为电视剧首播年份硬过滤。中文候选无结果时依次尝试其余标题别名。

- [ ] **Step 4: 实现详情、季度缓存和作品范围索引同步**

选择候选后只调用一次 `ITmdbClient.details`。缓存主海报和 `existingSeasons` 中实际存在的季度海报，稳定键使用 `workKey`。索引同步条件固定为 `item.workKey == work.workKey`。

~~~dart
await _indexRepository.updateMatching(
  work.sourceId,
  (item) => item.workKey == work.workKey,
  (item) => item.withEffectiveWorkTitle(metadata.title).replaceTmdb(
        tmdbId: metadata.id,
        tmdbTitle: metadata.title,
        tmdbOriginalTitle: metadata.originalTitle,
        tmdbOverview: metadata.overview,
        tmdbRating: metadata.rating,
        tmdbPosterUrl: metadata.posterUrl,
        tmdbBackdropUrl: metadata.backdropUrl,
        posterCachePath: posterCachePath,
      ),
);
~~~

- [ ] **Step 5: 运行服务、TMDB 客户端和缓存测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_service_test.dart test\tmdb_client_test.dart test\cloud_resource_tmdb_service_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交作品刮削服务**

~~~powershell
git add -- lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_poster_cache.dart test/cloud_work_tmdb_service_test.dart
git commit -m "按作品刮削 TMDB 季度海报"
~~~

### Task 8: 迁移旧文件记录并协调自动与手动匹配

**Files:**
- Create: `lib/services/cloud/cloud_work_tmdb_coordinator.dart`
- Create: `test/cloud_work_tmdb_coordinator_test.dart`
- Modify: `lib/repositories/cloud_resource_tmdb_repository.dart`
- Modify: `test/cloud_resource_tmdb_repository_test.dart`
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `test/cloud_source_cleanup_test.dart`

- [ ] **Step 1: 写一致迁移、冲突迁移和作品去重调度失败测试**

~~~dart
test('同作品旧文件记录一致时迁移一次并只调度一个作品', () async {
  await legacyRepository.upsertAll(<CloudResourceTmdbRecord>[
    legacyEpisode('s1e1', tmdbId: 42, customTitle: '弥留之国的爱丽丝'),
    legacyEpisode('s2e1', tmdbId: 42, customTitle: '弥留之国的爱丽丝'),
  ]);

  await coordinator.loadAndSchedule(tree);

  final records = await workRepository.getBySource('quark-a');
  expect(records.single.metadata?.id, 42);
  expect(records.single.scrapeTitleOverride, '弥留之国的爱丽丝');
  expect(service.scheduledWorkKeys, <String>[tree.works.single.workKey]);
});

test('同作品旧记录 TMDB 冲突时不自动选择', () async {
  await legacyRepository.upsertAll(<CloudResourceTmdbRecord>[
    legacyEpisode('s1e1', tmdbId: 42),
    legacyEpisode('s2e1', tmdbId: 99),
  ]);
  await coordinator.loadAndSchedule(tree);
  expect(
    (await workRepository.getBySource('quark-a')).single.status,
    CloudWorkTmdbStatus.conflict,
  );
  expect(service.scheduledWorkKeys, isEmpty);
});

CloudResourceTmdbRecord legacyEpisode(
  String id, {
  required int tmdbId,
  String? customTitle,
}) {
  return CloudResourceTmdbRecord.matched(
    sourceId: 'quark-a',
    remoteId: id,
    remotePath: '/影视/作品/$id.mkv',
    displayName: '$id.mkv',
    resourceKind: CloudResourceKind.standaloneVideo,
    metadata: TmdbMetadata(
      id: tmdbId,
      mediaType: TmdbMediaType.tv,
      title: '弥留之国的爱丽丝',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
    ),
    checkedAt: DateTime.utc(2026, 7, 20),
    customTitle: customTitle,
  );
}
~~~

- [ ] **Step 2: 运行协调器测试并确认类型不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_coordinator_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现来源加载、迁移和每作品一次调度**

协调器公开 `recordsByWorkKey`、`scrapingWorkKeys`、`completedCount`、`totalCount`，并以 `workKey` 去重。迁移只读取相同作品索引路径下的旧记录；一致 TMDB ID 迁移为 matched，冲突迁移为 conflict，旧 `customTitle` 迁移为 `scrapeTitleOverride`。

- [ ] **Step 4: 实现修改刮削名称和确认候选**

~~~dart
Future<CloudWorkTmdbRecord> saveScrapeTitle(
  CloudWorkIdentity work,
  String title,
) async {
  final normalized = title.trim();
  if (normalized.isEmpty) throw ArgumentError.value(title, 'title');
  final current = recordsByWorkKey[work.workKey] ??
      CloudWorkTmdbRecord.uncheckedFromWork(work, checkedAt: _now());
  final updated = current.copyWithScrapeTitle(normalized);
  await _repository.upsert(updated);
  await _indexRepository.updateMatching(
    work.sourceId,
    (item) => item.workKey == work.workKey,
    (item) => item.withEffectiveWorkTitle(normalized),
  );
  recordsByWorkKey[work.workKey] = updated;
  notifyListeners();
  return updated;
}
~~~

`selectCandidate` 调用 `CloudWorkTmdbService.select`，保存作品记录并只同步同 `workKey` 项。其他作品目录即使同名也不得传播。

`CloudLibraryController.delete` 删除来源时同时调用 `CloudWorkTmdbRepository.removeSource`。后续本地清理失败时按现有快照回滚顺序恢复作品记录；任何步骤都不调用网盘客户端修改接口。

- [ ] **Step 5: 运行迁移与协调测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_coordinator_test.dart test\cloud_resource_tmdb_repository_test.dart test\cloud_source_cleanup_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交协调器**

~~~powershell
git add -- lib/services/cloud/cloud_work_tmdb_coordinator.dart lib/repositories/cloud_resource_tmdb_repository.dart lib/providers/cloud_library_controller.dart test/cloud_work_tmdb_coordinator_test.dart test/cloud_resource_tmdb_repository_test.dart test/cloud_source_cleanup_test.dart
git commit -m "迁移并协调作品级网盘刮削"
~~~

### Task 9: 将资源集合改为季度卡和虚拟名称

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_collection.dart`
- Modify: `test/cloud_resource_collection_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_card_view_data.dart`
- Modify: `test/cloud_resource_card_view_data_test.dart`

- [ ] **Step 1: 写主海报墙集合直接产出三张季度卡的失败测试**

~~~dart
final collection = grouper.group(
  items: indexedItems,
  works: tree.works,
  recordsByWorkKey: <String, CloudWorkTmdbRecord>{
    record.workKey: record,
  },
  query: '',
);

expect(collection.groups, hasLength(3));
expect(
  collection.groups.map((group) => group.displayName),
  <String>[
    '弥留之国的爱丽丝 第 1 季',
    '弥留之国的爱丽丝 第 2 季',
    '弥留之国的爱丽丝 第 3 季',
  ],
);
expect(
  collection.groups.map((group) => group.seasonMetadata?.posterUrl),
  <String?>['/season-1.jpg', '/season-2.jpg', '/season-3.jpg'],
);
expect(collection.groups.last.videos.first.name, contains('S03E01'));
~~~

- [ ] **Step 2: 运行集合测试并确认仍为一剧一卡**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_collection_test.dart`

Expected: FAIL，`collection.groups` 只有一个电视剧组或名称仍为原始文件名。

- [ ] **Step 3: 重构组模型为一季一卡**

~~~dart
class CloudResourceMediaGroup {
  final String stableKey;
  final String workKey;
  final String displayName;
  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final CloudWorkTmdbRecord? record;
  final TmdbSeasonMetadata? seasonMetadata;

  bool get isSeries => seasonNumber != null;
  CloudFileEntry get anchor => videos.first;
}
~~~

电视剧稳定键为 `workKey + |season:季号`。电影稳定键保持作品键。视频 `CloudFileEntry.name` 使用索引 `displayName`，`remotePath` 和 `id` 保持真实值。

- [ ] **Step 4: 实现搜索和重复版本显示**

搜索值包含虚拟名称、TMDB 中文标题、原始标题、标题别名、索引 `remoteName` 和 `displayName`。重复季集号在虚拟名称后附加发布规格摘要或“版本 2”。

- [ ] **Step 5: 运行集合与卡片数据测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_collection_test.dart test\cloud_resource_card_view_data_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交季度集合**

~~~powershell
git add -- lib/pages/cloud/resources/cloud_resource_collection.dart lib/pages/cloud/resources/cloud_resource_card_view_data.dart test/cloud_resource_collection_test.dart test/cloud_resource_card_view_data_test.dart
git commit -m "按季度生成网盘海报卡"
~~~

### Task 10: 更新控制器为作品级刮削和虚拟条目

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_module.dart`
- Modify: `lib/app_module.dart`
- Modify: `test/cloud_resources_controller_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1: 写虚拟条目、刮削名称和跨季同步失败测试**

~~~dart
await controller.selectSource('quark-a');
expect(
  controller.collection.groups.map((group) => group.displayName),
  containsAll(<String>[
    '弥留之国的爱丽丝 第 1 季',
    '弥留之国的爱丽丝 第 2 季',
    '弥留之国的爱丽丝 第 3 季',
  ]),
);

final thirdSeason = controller.collection.groups.last;
await controller.saveScrapeTitle(thirdSeason, '弥留之国的爱丽丝');
expect(
  controller.collection.groups.every(
    (group) => group.displayName.startsWith('弥留之国的爱丽丝'),
  ),
  isTrue,
);
expect(controller.detailsFor(thirdSeason.videos.first).remoteName, '01.mkv');
~~~

- [ ] **Step 2: 运行控制器测试并确认仍使用文件级记录**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart`

Expected: FAIL，`saveScrapeTitle` 或作品级 records 不存在。

- [ ] **Step 3: 注入作品仓库与协调器**

控制器字段改为 `CloudWorkTmdbCoordinator`，并从 `CloudMediaIndexSnapshot` 重建作品。模块中所有实例共享同一个 `CloudMediaIndexRepository` 和 `CloudWorkTmdbRepository`，禁止分别创建不同仓库导致状态分裂。

~~~dart
Map<String, CloudWorkTmdbRecord> get workTmdbRecords =>
    _workTmdbCoordinator?.recordsByWorkKey ??
    const <String, CloudWorkTmdbRecord>{};

CloudResourceCollection get collection => _collectionGrouper.group(
      items: _indexedItems.values.toList(growable: false),
      works: works,
      recordsByWorkKey: workTmdbRecords,
      query: query,
    );
~~~

- [ ] **Step 4: 将 TMDB 操作改为作品范围**

新增 `tmdbDraftForGroup`、`searchWorkTmdb`、`applyWorkTmdbCandidate`、`saveScrapeTitle` 和 `rematchWork`。删除页面对单个视频传播候选列表的依赖；协调器通过 `workKey` 自行确定范围。

- [ ] **Step 5: 运行控制器和集成测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart test\cloud_library_integration_test.dart test\cloud_resource_tmdb_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交控制器联动**

~~~powershell
git add -- lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resources_module.dart lib/app_module.dart test/cloud_resources_controller_test.dart test/cloud_library_integration_test.dart
git commit -m "按作品协调网盘刮削"
~~~

### Task 11: 主海报墙显示季度海报并只显示虚拟名称

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Create: `lib/pages/cloud/resources/cloud_media_details_dialog.dart`
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `test/cloud_resources_flat_library_test.dart`
- Modify: `test/cloud_tmdb_library_ui_test.dart`

- [ ] **Step 1: 写三张季度海报、虚拟分集名和详情原名失败测试**

~~~dart
expect(find.text('弥留之国的爱丽丝 第 1 季'), findsOneWidget);
expect(find.text('弥留之国的爱丽丝 第 2 季'), findsOneWidget);
expect(find.text('弥留之国的爱丽丝 第 3 季'), findsOneWidget);
expect(find.byKey(const ValueKey<String>('season-poster-1')), findsOneWidget);
expect(find.byKey(const ValueKey<String>('season-poster-2')), findsOneWidget);
expect(find.byKey(const ValueKey<String>('season-poster-3')), findsOneWidget);

await tester.tap(find.text('弥留之国的爱丽丝 第 3 季'));
await tester.pumpAndSettle();
expect(find.text('弥留之国的爱丽丝 S03E01.mkv'), findsOneWidget);
expect(find.text('01.mkv'), findsNothing);

await tester.tap(find.byTooltip('媒体详情'));
await tester.pumpAndSettle();
expect(find.text('01.mkv'), findsOneWidget);
expect(find.textContaining('/第三季（2025）4K DV&HDR/01.mkv'), findsOneWidget);
~~~

- [ ] **Step 2: 运行页面测试并确认旧 UI 仍为整剧主海报**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_resources_flat_library_test.dart`

Expected: FAIL。

- [ ] **Step 3: 让海报墙消费季度元数据**

`CloudResourcePosterWall` 的 cover 优先使用 `group.seasonMetadata.posterCachePath` 和 `posterUrl`，再回退作品主海报。卡片 key 使用 `season-poster-季号`，标题使用 `group.displayName`，副标题显示实际集数。

- [ ] **Step 4: 让选集弹层只显示一个季度**

删除多季度循环；标题使用 `group.displayName`，视频标题使用 `CloudFileEntry.name` 的虚拟名称。播放回调仍返回携带真实 `id` 和 `remotePath` 的 `CloudFileEntry`。

- [ ] **Step 5: 增加媒体详情和修改刮削名称入口**

`CloudMediaDetailsDialog` 显示 `remoteName`、`remotePath`、虚拟名称、作品标题、季集号和发布规格，不显示 Cookie、请求头或播放直链。菜单“修改剧名”改为“修改刮削名称”，保存后调用 `controller.saveScrapeTitle`。

- [ ] **Step 6: 运行页面、TMDB 和播放回归**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_resources_flat_library_test.dart test\cloud_tmdb_library_ui_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交季度 UI**

~~~powershell
git add -- lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/cloud/resources/cloud_media_details_dialog.dart test/cloud_resources_page_test.dart test/cloud_resources_flat_library_test.dart test/cloud_tmdb_library_ui_test.dart
git commit -m "展示网盘季度海报和虚拟名称"
~~~

### Task 12: 补齐安全、迁移和真实目录端到端回归

**Files:**
- Modify: `test/cloud_library_integration_test.dart`
- Modify: `test/cloud_source_cleanup_test.dart`
- Modify: `test/cloud_series_match_rule_repository_test.dart`
- Modify: `test/cloud_resource_collection_test.dart`
- Modify: `test/cloud_media_indexer_test.dart`

- [ ] **Step 1: 增加真实目录端到端测试**

端到端测试从假网盘客户端扫描设计夹具，自动匹配 TMDB 42，断言：

~~~dart
expect(controller.collection.groups, hasLength(3));
expect(fakeTmdbClient.searchCalls, 1);
expect(fakeTmdbClient.detailCalls, 1);
expect(
  controller.collection.groups.map((group) => group.seasonMetadata?.seasonNumber),
  <int>[1, 2, 3],
);
final driveInterface =
    File('lib/services/cloud/cloud_drive_client.dart').readAsStringSync();
for (final forbidden in <String>['rename(', 'move(', 'delete(']) {
  expect(driveInterface, isNot(contains(forbidden)));
}
~~~

- [ ] **Step 2: 增加失败与离线回归**

覆盖无 API Key、TMDB 搜索失败、单季海报缓存失败、一个目录读取失败和旧索引识别版本为 0。每个用例断言季度卡仍存在且视频可解析播放。

- [ ] **Step 3: 增加多作品、跨来源和规模矩阵**

~~~dart
final quarkTree = resolver.resolve(
  sourceId: 'quark-a',
  configuredRoots: quarkFixture.roots,
  directoryEntries: quarkFixture.directoryEntries,
  minSizeBytes: 100,
);
final openListTree = resolver.resolve(
  sourceId: 'openlist-a',
  configuredRoots: openListFixture.roots,
  directoryEntries: openListFixture.directoryEntries,
  minSizeBytes: 100,
);
expect(quarkTree.works, hasLength(50));
expect(openListTree.works, hasLength(50));
expect(
  quarkTree.works.map((work) => work.workKey).toSet()
      .intersection(openListTree.works.map((work) => work.workKey).toSet()),
  isEmpty,
);
await coordinator.loadAndSchedule(quarkTree);
expect(fakeWorkService.scheduledWorkKeys.toSet(), hasLength(50));
~~~

矩阵同时包含中文、英文、中英双语、数字标题、动漫发布组、电影、特别篇、同名异目录以及四种季度写法。断言每个作品仅接收自己的虚拟名称、TMDB 记录和季度海报。

- [ ] **Step 4: 增加禁止作品硬编码与清理安全断言**

~~~dart
for (final path in <String>[
  'lib/services/media_name_analyzer.dart',
  'lib/services/cloud/cloud_media_tree_resolver.dart',
  'lib/services/cloud/cloud_work_tmdb_service.dart',
]) {
  final source = File(path).readAsStringSync();
  for (final forbidden in <String>[
    '弥留之国的爱丽丝',
    'Alice in Borderland',
    'tmdbId == 42',
  ]) {
    expect(source, isNot(contains(forbidden)), reason: '$path: $forbidden');
  }
}
~~~

删除来源、索引和缓存只调用本地仓库与缓存目录；假 `CloudDriveClient` 不增加任何删除或重命名方法。保留广告远程条目，断言仅不进入媒体集合。

- [ ] **Step 5: 运行网盘完整相关测试组**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_library_integration_test.dart test\cloud_source_cleanup_test.dart test\cloud_media_indexer_test.dart test\cloud_resource_collection_test.dart test\cloud_work_tmdb_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交端到端回归**

~~~powershell
git add -- test/cloud_library_integration_test.dart test/cloud_source_cleanup_test.dart test/cloud_series_match_rule_repository_test.dart test/cloud_resource_collection_test.dart test/cloud_media_indexer_test.dart
git commit -m "覆盖网盘识别刮削端到端场景"
~~~

### Task 13: 更新 2.1.18 版本和普通用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 先将版本测试期望改为 2.1.18 并确认失败**

~~~dart
const expectedVersion = '2.1.18';
const expectedBuildNumber = '20118';

test('二点一十八说明季度海报和虚拟名称', () {
  final entries = versionHistoryForCurrent('2.1.18');
  expect(entries, hasLength(1));
  expect(entries.single.changes.join(), contains('每一季'));
  expect(entries.single.changes.join(), contains('剧名'));
  expect(entries.single.changes.join(), contains('不会修改网盘文件'));
});
~~~

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，当前仍为 2.1.17。

- [ ] **Step 2: 同步版本与面向普通用户的发布说明**

精确更新：

- `pubspec.yaml`: `version: 2.1.18+20118`
- `msix_config.msix_version`: `2.1.18.0`
- `AppVersion.current`: `2.1.18`
- 版本历史、更新弹窗和发布说明描述“每季独立海报、纯数字分集识别、应用内规范名称、不修改网盘文件”。

- [ ] **Step 3: 运行版本测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 4: 提交发布信息**

~~~powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "更新二点一十八发布信息"
~~~

### Task 14: 完整验证、Windows Release、MSIX 和 Git 收尾

**Files:**
- Verify: all modified source and test files
- Deliver: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `%USERPROFILE%\Desktop\看影音-2.1.18.msix`

- [ ] **Step 1: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: PASS，零失败。

- [ ] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`

- [ ] **Step 3: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `Built build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 4: 生成签名 MSIX**

从当前用户签名目录读取 `certificate.pfx` 与 DPAPI 加密密码。密码只在当前 PowerShell 进程内转换，禁止输出或写入明文文件。

~~~powershell
$secure = Import-Clixml -LiteralPath "$env:USERPROFILE\.kanyingyin\signing\certificate-password.clixml"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  D:\flutter\bin\dart.bat run msix:create --build-windows false --sign-msix true --certificate-path "$env:USERPROFILE\.kanyingyin\signing\certificate.pfx" --certificate-password $plainPassword
} finally {
  $plainPassword = $null
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
~~~

Expected: 生成已签名 `kanyingyin.msix`。

- [ ] **Step 5: 验证清单、签名和桌面副本**

解包读取 `AppxManifest.xml` 并断言：

- Identity Name = `com.kanyingyin.player`
- Version = `2.1.18.0`
- Publisher = `CN=KanYingYin`
- ProcessorArchitecture = `x64`
- `AppxSignature.p7x` 存在
- `Get-AuthenticodeSignature` 状态为 `Valid`

复制为 `%USERPROFILE%\Desktop\看影音-2.1.18.msix`，并比较源包与桌面包 SHA-256 相同。

- [ ] **Step 6: 检查状态和关键 diff**

Run: `git status --short`、`git diff --check`、`git log --oneline -15`

只提交本轮相关修改；保留 `.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md` 的现有用户修改。若源码均已按任务提交，不创建空提交。

- [ ] **Step 7: 最终复验**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: PASS。报告 Release、MSIX 清单版本、签名状态、桌面路径和 SHA-256。
