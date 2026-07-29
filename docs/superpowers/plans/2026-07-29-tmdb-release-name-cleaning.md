# TMDB 发布名称清洗 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将用户列出的发布站、集数、语言、片源、编码、音轨、季度和合集前后缀从 TMDB 搜索词中清除，同时保留片名并把年份、季号写入结构化匹配条件。

**Architecture:** 继续使用 `TmdbResourceNameCleaner` 作为本地和网盘共用的发布信息清洗边界，只增加有明确特征的发布站括号、系列编号和发布尾缀规则。`CloudMediaNameParser` 与 `TmdbScrapePolicy` 仍负责年份、季集字段；删除年份前必须确认仍有非年份标题，避免破坏 `[REC]`、`1923` 和普通数字片名。

**Tech Stack:** Flutter 3.41.9、Dart RegExp、flutter_test

---

### Task 1: 用用户样本固定网盘解析结果

**Files:**
- Modify: `test/cloud_media_name_parser_test.dart`

- [ ] **Step 1: 写入全部前后缀参数化测试**

```dart
test('用户提供的发布前后缀只保留片名和结构化信息', () {
  final cases = <({String name, int? year, int? season})>[
    (name: '片名【日剧】全52集.国语配音+字.珍藏版.1996.1080P', year: 1996, season: null),
    (name: '片名.2008.Eng.Fre.Ger.Ita.Por.Spa.Cze.Hun.Pol.Rus.Tha.Jpn.2160p.BluRay.Hybrid.Remux.DV.HDR.HEVC.DTS-HD.MA-SGF', year: 2008, season: null),
    (name: '片名【高清剧集网发布 www.DDHDTV.com】[全46集][国语配音+中文字幕].S01.2006.1080p.Hami.WEB-DL.H264.AAC-LeloveTV', year: 2006, season: 1),
    (name: '片名 剧场版11部', year: null, season: null),
    (name: '片名【高清剧集网发布 www.PTHDTV.com】[全12集][简繁英字幕].S01.1080p.HBOMax.WEB-DL.DDP2.0.H.264-BlackTV', year: null, season: 1),
    (name: '片名 全集4K日语中字', year: null, season: null),
    (name: '034201_（系列）片名', year: null, season: null),
    (name: '片名【高清影视之家发布 www.SSDDSE.com】[高码版][国粤多音轨+中文字幕].2016.2160p.HQ.WEB-DL.H265.DTS5.1-DreamHD', year: 2016, season: null),
    (name: '片名【高清剧集网 www.BTHDTV.com】[全30集][国语配音+中文字幕].2005.4K.WEB-DL.H265.AAC-HotWEB', year: 2005, season: null),
    (name: '片名[全16集][中文字幕].S01.2160p.TVING.WEB-DL.H265.AAC-ColorTV', year: null, season: 1),
    (name: '片名【高清剧集网发布 www.DDHDTV.com】[全52集][国语配音+中文字幕].1997.1080p.KKTV.WEB-DL.H264.AAC-Huawei', year: 1997, season: null),
    (name: '片名【高清剧集网发布 www.DDHDTV.com】第二季[全6集][简繁英字幕].S02.2014.1080p.BluRay.x264.FLAC.2.0-ZeroTV', year: 2014, season: 2),
    (name: '片名【高清影视之家发布 www.SSDDSE.com】[高码版][国粤多音轨+中文字幕].2012.2160p.HQ.WEB-DL.H265.DTS5.1.2Audio-DreamHD', year: 2012, season: null),
    (name: '片名.2012.PROPER.2160p.BluRay.REMUX.HEVC.DTS-HD.MA.5.1-FGT', year: 2012, season: null),
    (name: '片名【高清剧集网发布 www.DDHDTV.com】第一季[全6集][中文字幕].S01.BluRay.1080p.DTS-HDMA2.0.x264-BlackTV', year: null, season: 1),
    (name: '片名.2005.Eng.Fre.Ger.Ita.Por.Spa.Cze.Hun.Pol.Rus.Tha.Tur.Chi.Jpn.2160p.BluRay.Hybrid.Remux.DV.HDR.HEVC.DTS-HD.MA-SGF', year: 2005, season: null),
    (name: '片名 1-2部合集 4K原盘 中文字幕', year: null, season: null),
    (name: '片名【高清剧集网发布 www.PTHDTV.com】[全10集][简繁英字幕].S01.2160p.NF.WEB-DL.DDP5.1.Atmos.H.265-BlackTV', year: null, season: 1),
    (name: '片名【高清剧集网 www.BTHDTV.com】第五季[杜比视界版本][全6集][简繁英字幕].S05.2019.NF.WEB-DL.2160p.HEVC.DV.DDP-Xiaomi', year: 2019, season: 5),
    (name: '片名【高清剧集网发布 www.DDHDTV.com】第三季[全6集][简繁英字幕].S03.2016.1080p.BluRay.x264.DTS-ZeroTV', year: 2016, season: 3),
    (name: '片名【高清剧集网发布 www.DDHDTV.com】第四季[全6集][简繁英字幕].S04.2017.1080p.BluRay.x264.DTS-ZeroTV', year: 2017, season: 4),
    (name: '片名【高清剧集网发布 www.QQHDTV.com】第六季[全6集][简繁英字幕].S06.2160p.NF.WEB-DL.DDP5.1.Atmos.HEVC-ColorTV', year: null, season: 6),
  ];

  for (final item in cases) {
    final draft = parser.parse(originalName: item.name, isDirectory: true);
    expect(draft.searchTitle, '片名', reason: item.name);
    expect(draft.year, item.year, reason: item.name);
    expect(draft.seasonNumber, item.season, reason: item.name);
    expect(
      draft.mediaTypeMode,
      item.season == null ? TmdbMediaTypeMode.auto : TmdbMediaTypeMode.tv,
      reason: item.name,
    );
  }
});
```

- [ ] **Step 2: 运行网盘名称解析测试并确认样本失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_media_name_parser_test.dart`

Expected: FAIL，失败输出显示当前未清理的发布站、语言或尾缀。

- [ ] **Step 3: 提交仅含失败测试的检查点**

```powershell
git add -- test/cloud_media_name_parser_test.dart
git commit -m "测试 TMDB 发布名称清洗样本"
```

### Task 2: 扩展共用发布名称清洗器

**Files:**
- Modify: `lib/services/tmdb/tmdb_resource_name_cleaner.dart`
- Modify: `test/tmdb_resource_name_cleaner_test.dart`

- [ ] **Step 1: 增加发布括号、系列编号和安全回归测试**

```dart
test('清除发布站括号资源说明和系列编号前缀', () {
  final cases = <String, String>{
    '作品【高清剧集网发布 www.DDHDTV.com】[全46集][国语配音+中文字幕]': '作品',
    '作品【高清影视之家发布 www.SSDDSE.com】[高码版][国粤多音轨+中文字幕]': '作品',
    '034201_（系列）作品': '作品',
    '作品 全集4K日语中字': '作品',
    '作品 剧场版11部': '作品',
    '作品 1-2部合集 4K原盘 中文字幕': '作品',
  };
  for (final entry in cases.entries) {
    expect(cleaner.clean(entry.key), entry.value, reason: entry.key);
  }
});

test('发布规则不删除正式括号标题或数字作品名', () {
  expect(cleaner.clean('[REC] (2007).mkv'), '[REC] (2007)');
  expect(cleaner.clean('1923.mkv'), '1923');
  expect(cleaner.clean('The 100.mkv'), 'The 100');
  expect(cleaner.clean('作品【导演收藏】.mkv'), '作品【导演收藏】');
});
```

- [ ] **Step 2: 实现有边界的括号和前后缀规则**

在清洗器中增加以下模式；发布站只按明确站点文字或域名识别，不能删除所有括号：

```dart
static final RegExp _seriesNumberPrefixPattern = RegExp(
  r'^\s*\d{6}_（系列）\s*',
  unicode: true,
);
static final RegExp _releaseSitePattern = RegExp(
  r'(?:高清剧集网|高清影视之家|(?:DD|PT|BT|QQ)HDTV\.com|SSDDSE\.com|发布\s+www\.)',
  caseSensitive: false,
);
static final RegExp _releaseDescriptionPattern = RegExp(
  r'(?:全\s*\d+\s*集|高码版|杜比视界版本|国语配音|国粤多音轨|简繁英字幕|中文字幕|字幕|日剧)',
  caseSensitive: false,
);
static final RegExp _collectionSuffixPattern = RegExp(
  r'(?:剧场版\s*\d+\s*部|\d+\s*[-~至]\s*\d+\s*部合集|全集\s*4K?\s*日语中字|全集|全\s*\d+\s*集)',
  caseSensitive: false,
);
static final RegExp _chineseReleasePhrasePattern = RegExp(
  r'(?:国语配音\+?字?|国粤多音轨|简繁英字幕|中文字幕|日语中字|高码版|珍藏版|杜比视界版本|原盘)',
  caseSensitive: false,
);
static final RegExp _languageTokenPattern = RegExp(
  r'(?<![A-Za-z0-9])(?:Eng|Fre|Ger|Ita|Por|Spa|Cze|Hun|Pol|Rus|Tha|Tur|Chi|Jpn)(?![A-Za-z0-9])',
  caseSensitive: false,
);
static final RegExp _releaseGroupPattern = RegExp(
  r'(?:[-._ ](?:SGF|FGT|LeloveTV|BlackTV|DreamHD|HotWEB|ColorTV|ZeroTV|Huawei|Xiaomi))\s*$',
  caseSensitive: false,
);
```

在 `_releaseTokenPattern` 中补充 `hybrid|proper|hami|tving|netflix|nf|kktv|hq|2audio`。`clean` 的完整处理顺序调整为：

```dart
String clean(String value) {
  var result = value.trim().replaceFirst(_knownExtensionPattern, '');
  result = result.replaceFirst(_seriesNumberPrefixPattern, '');
  result = result.replaceAllMapped(_bracketPattern, (match) {
    final content = match.group(1) ?? match.group(2) ?? '';
    final isReleaseBlock = _releaseTokenPattern.hasMatch(content) ||
        _releaseSitePattern.hasMatch(content) ||
        _releaseDescriptionPattern.hasMatch(content);
    return isReleaseBlock ? ' ' : match.group(0)!;
  });
  result = result
      .replaceAll(_collectionSuffixPattern, ' ')
      .replaceAll(_chineseReleasePhrasePattern, ' ')
      .replaceAll(_languageTokenPattern, ' ')
      .replaceAll(_releaseGroupPattern, ' ')
      .replaceAll(_releaseTokenPattern, ' ')
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'^[\s&+,\-–—:：]+|[\s&+,\-–—:：]+$'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return result;
}
```

语言缩写始终通过 `_languageTokenPattern` 的完整三字母边界逐个删除；不得增加模糊的任意三字母匹配，也不得从未知英文单词处截断标题。

- [ ] **Step 3: 运行清洗器和网盘解析测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_resource_name_cleaner_test.dart test/cloud_media_name_parser_test.dart`

Expected: 清洗器安全回归 PASS；用户全部样本的 `searchTitle` 为“片名”。

- [ ] **Step 4: 提交共用清洗规则**

```powershell
git add -- lib/services/tmdb/tmdb_resource_name_cleaner.dart test/tmdb_resource_name_cleaner_test.dart
git commit -m "扩充 TMDB 发布名称清洗规则"
```

### Task 3: 统一年份与季号结构化处理

**Files:**
- Modify: `lib/services/cloud/cloud_media_name_parser.dart`
- Modify: `lib/services/tmdb/tmdb_scrape_policy.dart`
- Modify: `test/cloud_media_name_parser_test.dart`
- Modify: `test/tmdb_scrape_policy_test.dart`

- [ ] **Step 1: 增加本地入口与纯数字片名测试**

```dart
test('本地搜索计划清理发布站尾缀并保留年份筛选', () {
  const subject = TmdbScrapeSubject(
    stableKey: 'release-title',
    titleCandidates: <String>[
      '片名【高清剧集网发布 www.DDHDTV.com】第二季[全6集][简繁英字幕].S02.2014.1080p.BluRay.x264.FLAC.2.0-ZeroTV',
    ],
    seasonNumbers: <int>{2},
    mediaEvidence: TmdbMediaEvidence.tv,
  );
  final plan = policy.build(subject, const TmdbScrapeOptions.defaults());
  expect(plan.queries, <String>['片名']);
  expect(plan.year, 2014);
  expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.tv]);
});

test('纯年份数字作品名不会被清空', () {
  const subject = TmdbScrapeSubject(
    stableKey: 'numeric-title',
    titleCandidates: <String>['1923'],
  );
  final plan = policy.build(subject, const TmdbScrapeOptions.defaults());
  expect(plan.queries, <String>['1923']);
  expect(plan.year, 1923);
});
```

- [ ] **Step 2: 运行本地策略测试并确认纯数字标题失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_scrape_policy_test.dart`

Expected: FAIL；当前 `_cleanTitle` 会把 `1923` 清为空字符串。

- [ ] **Step 3: 仅在仍有标题时删除年份**

```dart
String _cleanTitle(String value) {
  final cleaned = _cleaner
      .clean(value)
      .replaceAll(_seasonEpisodePattern, ' ')
      .replaceAll(_chineseSeasonPattern, ' ')
      .replaceAll(_englishSeasonPattern, ' ')
      .replaceAll(_chineseEpisodePattern, ' ')
      .replaceAll(RegExp(r'[（(]\s*[)）]'), ' ')
      .replaceAll(RegExp(r'\s+-\s+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final withoutYear = cleaned
      .replaceAll(_yearPattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return withoutYear.isEmpty ? cleaned : withoutYear;
}
```

在 `CloudMediaNameParser` 中继续先从原始名称提取年份，再调用清洗器；把 `_cleanTitle` 改为接收提取出的年份并使用以下辅助方法。季号识别继续以原始名称为准，因此发布站清洗不会丢失 S01 至 S06。

```dart
String _removeYearWhenTitleRemains(String value, int? year) {
  if (year == null) return value;
  final yearPattern = RegExp(
    '(?:^|[\\s._(（])${RegExp.escape('$year')}(?=\$|[\\s._)）])',
  );
  final withoutYear = value
      .replaceAll(yearPattern, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return withoutYear.isEmpty ? value : withoutYear;
}
```

调用关系固定为：

```dart
final year = yearMatch == null ? null : int.tryParse(yearMatch.group(1)!);
final searchTitle = _removeYearWhenTitleRemains(
  _cleanTitle(titleSource),
  year,
);
```

- [ ] **Step 4: 运行本地、网盘和清洗器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_resource_name_cleaner_test.dart test/cloud_media_name_parser_test.dart test/tmdb_scrape_policy_test.dart`

Expected: PASS，用户样本、本地入口和安全回归全部通过。

- [ ] **Step 5: 提交结构化处理**

```powershell
git add -- lib/services/cloud/cloud_media_name_parser.dart lib/services/tmdb/tmdb_scrape_policy.dart test/cloud_media_name_parser_test.dart test/tmdb_scrape_policy_test.dart
git commit -m "统一 TMDB 年份季度名称解析"
```

### Task 4: 验证名称清洗子计划

**Files:**
- Verify only

- [ ] **Step 1: 运行 TMDB 名称相关测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_resource_name_cleaner_test.dart test/cloud_media_name_parser_test.dart test/tmdb_scrape_policy_test.dart test/tmdb_prepared_search_test.dart`

Expected: PASS，0 failures。

- [ ] **Step 2: 运行静态分析并检查差异**

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
git status --short
git diff --check
```

Expected: `No issues found!`，没有未提交的名称清洗代码。
