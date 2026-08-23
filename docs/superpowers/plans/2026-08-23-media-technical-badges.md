# 媒体清晰度与杜比标签 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为本地和个人网盘媒体的海报及全部选集界面显示统一的 4K、2K、1080P、杜比视界、HDR10+、HDR 和杜比全景声标签。

**Architecture:** 新增一个纯 Dart 技术标签解析器，复用 `MediaNameAnalyzer`、本地视频宽高和现有文件名，不增加依赖或持久化字段。新增一个共享 Flutter 标签行组件，由 `ImmersiveMediaCard`、本地/网盘选集和播放器选集复用；海报汇总最高规格，选集显示单文件规格。

**Tech Stack:** Flutter 3.41.9、Dart、Material、flutter_test、现有 `MediaNameAnalyzer`

---

## 文件结构

- 新建 `lib/features/library/application/media_technical_badges.dart`：纯 Dart 标签模型、单文件解析和多文件汇总。
- 新建 `test/media_technical_badges_test.dart`：清晰度、杜比/HDR、去重和汇总规则。
- 修改 `lib/features/library/presentation/immersive_media_card.dart`：共享标签行组件和海报左上常驻层。
- 修改 `lib/features/library/application/media_card_info.dart`：给统一卡片信息增加技术标签并按作品汇总。
- 修改 `lib/features/library/application/library_media_view_data_builder.dart`、`lib/features/library/presentation/library_media_grid.dart`：本地海报传递技术标签。
- 修改 `lib/pages/cloud/resources/cloud_resource_card_view_data.dart`、`lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：网盘海报传递技术标签。
- 修改 `lib/features/library/presentation/media_category_page.dart`：分类海报与分类选集。
- 修改 `lib/pages/local/local_series_detail_page.dart`、`lib/pages/local/library_sheet.dart`：本地全部选集入口。
- 修改 `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`：网盘选集。
- 修改 `lib/features/library/presentation/media_library_details_dialog.dart`：媒体详情资源列表。
- 修改 `lib/pages/video/video_page.dart`：播放器右侧选集。
- 修改对应现有测试文件：保持组件布局、点击、焦点和 TV 兼容行为。
- 修改 `pubspec.yaml`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：版本与用户文案。

## Task 1：共享技术标签解析器

**Files:**
- Create: `lib/features/library/application/media_technical_badges.dart`
- Create: `test/media_technical_badges_test.dart`

- [ ] **Step 1：先写清晰度失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';

void main() {
  const resolver = MediaTechnicalBadgeResolver();

  test('实际宽高优先并兼容竖屏，只显示一个最高档清晰度', () {
    expect(
      resolver.resolve(
        names: const ['误标.1080p.mkv'],
        videoWidth: 3840,
        videoHeight: 2160,
      ).map((item) => item.label),
      ['4K'],
    );
    expect(
      resolver.resolve(
        names: const ['竖屏视频.mkv'],
        videoWidth: 1440,
        videoHeight: 2560,
      ).map((item) => item.label),
      ['2K'],
    );
    expect(
      resolver.resolve(names: const ['电影.720p.mkv']),
      isEmpty,
    );
    expect(
      resolver.resolve(
        names: const ['误标.4K.mkv'],
        videoWidth: 1280,
        videoHeight: 720,
      ),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2：运行测试并确认因类型不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\media_technical_badges_test.dart`

Expected: FAIL，提示无法找到 `media_technical_badges.dart` 或 `MediaTechnicalBadgeResolver`。

- [ ] **Step 3：写最小标签模型和清晰度实现**

```dart
import 'package:kanyingyin/services/media_name_analyzer.dart';

enum MediaTechnicalBadgeKind { resolution, dolbyVision, hdr, dolbyAtmos }

class MediaTechnicalBadge {
  const MediaTechnicalBadge(this.label, this.kind);

  final String label;
  final MediaTechnicalBadgeKind kind;
}

class MediaTechnicalBadgeResolver {
  const MediaTechnicalBadgeResolver();

  List<MediaTechnicalBadge> resolve({
    required Iterable<String> names,
    String? resolution,
    int? videoWidth,
    int? videoHeight,
  }) {
    final sources = names.where((name) => name.trim().isNotEmpty).toList();
    final parsed = sources
        .map((name) => const MediaNameAnalyzer()
            .analyze(name, isDirectory: false)
            .releaseTags)
        .toList(growable: false);
    final hasDimensions = videoWidth != null &&
        videoHeight != null &&
        videoWidth > 0 &&
        videoHeight > 0;
    final resolutionLabel = hasDimensions
        ? _fromDimensions(videoWidth, videoHeight)
        : _normalizeResolution(resolution) ??
            _bestResolution(parsed.map((tags) => tags.resolution));
    return <MediaTechnicalBadge>[
      if (resolutionLabel != null)
        MediaTechnicalBadge(
          resolutionLabel,
          MediaTechnicalBadgeKind.resolution,
        ),
    ];
  }

  String? _fromDimensions(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final long = width > height ? width : height;
    final short = width > height ? height : width;
    if (long >= 3840 && short >= 2160) return '4K';
    if (long >= 2560 && short >= 1440) return '2K';
    if (long >= 1920 && short >= 1080) return '1080P';
    return null;
  }

  String? _bestResolution(Iterable<String?> values) {
    String? result;
    for (final value in values) {
      final candidate = _normalizeResolution(value);
      if (_rank(candidate) > _rank(result)) result = candidate;
    }
    return result;
  }

  String? _normalizeResolution(String? value) {
    return switch (value?.trim().toLowerCase()) {
      '4k' || '2160p' => '4K',
      '2k' || '1440p' => '2K',
      '1080p' => '1080P',
      _ => null,
    };
  }

  int _rank(String? value) => switch (value) {
        '4K' => 3,
        '2K' => 2,
        '1080P' => 1,
        _ => 0,
      };
}
```

- [ ] **Step 4：运行测试并确认清晰度测试通过**

Run: `D:\flutter\bin\flutter.bat test test\media_technical_badges_test.dart`

Expected: PASS。

- [ ] **Step 5：先补杜比、HDR 和汇总失败测试**

```dart
test('识别杜比视界 HDR10+ HDR 和全景声并正确去重', () {
  expect(
    resolver
        .resolve(names: const [
          'Movie.2160p.DoVi.HDR10Plus.Dolby.Atmos.mkv',
        ])
        .map((item) => item.label),
    ['4K', '杜比视界', 'HDR10+', '杜比全景声'],
  );
  expect(
    resolver.resolve(names: const ['Movie.1080p.HDR10.mkv'])
        .map((item) => item.label),
    ['1080P', 'HDR'],
  );
});

test('作品汇总取最高清晰度并保留任一文件的影音规格', () {
  final result = resolver.aggregate([
    resolver.resolve(names: const ['E01.1080p.HDR.mkv']),
    resolver.resolve(names: const ['E02.2160p.DV.Atmos.mkv']),
  ]);
  expect(
    result.map((item) => item.label),
    ['4K', '杜比视界', 'HDR', '杜比全景声'],
  );
});
```

- [ ] **Step 6：运行测试并确认新断言失败**

Run: `D:\flutter\bin\flutter.bat test test\media_technical_badges_test.dart`

Expected: FAIL，当前只返回清晰度标签。

- [ ] **Step 7：补最小杜比/HDR 识别与汇总实现**

在 `resolve` 中把文件名与 `MediaNameAnalyzer.releaseTags` 合并判断；`HDR10+` 存在时不再加入普通 `HDR`：

```dart
final combined = sources.join(' ');
final dynamicRange = parsed.expand((tags) => tags.dynamicRange);
final audio = parsed.expand((tags) => tags.audio);
final hasDolbyVision = dynamicRange.any((value) => value == 'DV') ||
    RegExp(r'(?<![A-Za-z0-9])(?:DV|DoVi|Dolby[\s._-]*Vision)(?![A-Za-z0-9])',
            caseSensitive: false)
        .hasMatch(combined);
final hasHdr10Plus = RegExp(
  r'(?<![A-Za-z0-9])HDR10(?:\+|Plus)(?![A-Za-z0-9])',
  caseSensitive: false,
).hasMatch(combined);
final hasHdr = !hasHdr10Plus &&
    (dynamicRange.any((value) => value == 'HDR') ||
        RegExp(r'(?<![A-Za-z0-9])HDR(?:10)?(?![A-Za-z0-9+])',
                caseSensitive: false)
            .hasMatch(combined));
final hasAtmos = audio.any((value) => value == 'Atmos') ||
    RegExp(r'(?<![A-Za-z0-9])(?:Dolby[\s._-]*)?Atmos(?![A-Za-z0-9])',
            caseSensitive: false)
        .hasMatch(combined);

return <MediaTechnicalBadge>[
  if (resolutionLabel != null)
    MediaTechnicalBadge(resolutionLabel, MediaTechnicalBadgeKind.resolution),
  if (hasDolbyVision)
    const MediaTechnicalBadge(
      '杜比视界',
      MediaTechnicalBadgeKind.dolbyVision,
    ),
  if (hasHdr10Plus)
    const MediaTechnicalBadge('HDR10+', MediaTechnicalBadgeKind.hdr),
  if (hasHdr)
    const MediaTechnicalBadge('HDR', MediaTechnicalBadgeKind.hdr),
  if (hasAtmos)
    const MediaTechnicalBadge(
      '杜比全景声',
      MediaTechnicalBadgeKind.dolbyAtmos,
    ),
];
```

新增汇总方法，按固定顺序去重并只保留最高分辨率：

```dart
List<MediaTechnicalBadge> aggregate(
  Iterable<List<MediaTechnicalBadge>> sources,
) {
  final all = sources.expand((items) => items).toList(growable: false);
  final resolution = all
      .where((item) => item.kind == MediaTechnicalBadgeKind.resolution)
      .fold<MediaTechnicalBadge?>(
        null,
        (best, item) => _rank(item.label) > _rank(best?.label) ? item : best,
      );
  final labels = <String>{};
  return <MediaTechnicalBadge>[
    if (resolution != null) resolution,
    for (final kind in const [
      MediaTechnicalBadgeKind.dolbyVision,
      MediaTechnicalBadgeKind.hdr,
      MediaTechnicalBadgeKind.dolbyAtmos,
    ])
      for (final item in all.where((item) => item.kind == kind))
        if (labels.add(item.label)) item,
  ];
}
```

- [ ] **Step 8：运行解析器测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\media_technical_badges_test.dart`

Expected: PASS。

```powershell
git add lib/features/library/application/media_technical_badges.dart test/media_technical_badges_test.dart
git commit -m "功能：统一识别媒体技术标签"
```

## Task 2：共享标签组件与海报常驻层

**Files:**
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1：先写海报常驻和空列表失败测试**

在 `ImmersiveMediaCard` 测试组新增：

```dart
testWidgets('技术标签常驻海报左上且空列表不占位', (tester) async {
  Future<void> pump(List<MediaTechnicalBadge> badges) => tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 260,
            height: 380,
            child: ImmersiveMediaCard(
              cover: const ColoredBox(color: Colors.blue),
              title: '测试电影',
              overlayMode: ImmersiveMediaCardOverlayMode.hover,
              technicalBadges: badges,
            ),
          ),
        ),
      );

  await pump(const [
    MediaTechnicalBadge('4K', MediaTechnicalBadgeKind.resolution),
    MediaTechnicalBadge('杜比视界', MediaTechnicalBadgeKind.dolbyVision),
  ]);
  expect(find.byKey(const ValueKey('media-technical-badges-poster')), findsOneWidget);
  expect(find.text('4K'), findsOneWidget);
  expect(find.text('杜比视界'), findsOneWidget);
  final card = tester.getRect(find.byType(ImmersiveMediaCard));
  final row = tester.getRect(
    find.byKey(const ValueKey('media-technical-badges-poster')),
  );
  expect(row.left, greaterThanOrEqualTo(card.left + 8));
  expect(row.top, greaterThanOrEqualTo(card.top + 8));

  await pump(const []);
  expect(find.byKey(const ValueKey('media-technical-badges-poster')), findsNothing);
});
```

- [ ] **Step 2：运行测试并确认构造参数不存在**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart --plain-name "技术标签常驻海报左上且空列表不占位"`

Expected: FAIL，`technicalBadges` 未定义。

- [ ] **Step 3：实现共享 `MediaTechnicalBadgeRow` 和海报层**

给 `ImmersiveMediaCard` 增加：

```dart
this.technicalBadges = const <MediaTechnicalBadge>[],
```

```dart
final List<MediaTechnicalBadge> technicalBadges;
```

在现有 `Stack` 中、`trailing` 之前加入：

```dart
if (widget.technicalBadges.isNotEmpty)
  Positioned(
    left: 10,
    top: 10,
    right: widget.trailing == null ? 10 : 42,
    child: IgnorePointer(
      child: MediaTechnicalBadgeRow(
        key: const ValueKey('media-technical-badges-poster'),
        badges: widget.technicalBadges,
        poster: true,
      ),
    ),
  ),
```

同文件新增共享组件；使用 `Wrap`，不新增动画或依赖：

```dart
class MediaTechnicalBadgeRow extends StatelessWidget {
  const MediaTechnicalBadgeRow({
    super.key,
    required this.badges,
    this.poster = false,
  });

  final List<MediaTechnicalBadge> badges;
  final bool poster;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final badge in badges)
          DecoratedBox(
            key: ValueKey('media-technical-badge-${badge.label}'),
            decoration: BoxDecoration(
              color: _color(badge.kind),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: poster ? 7 : 6,
                vertical: poster ? 4 : 3,
              ),
              child: Text(
                badge.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
              ),
            ),
          ),
      ],
    );
  }

  Color _color(MediaTechnicalBadgeKind kind) => switch (kind) {
        MediaTechnicalBadgeKind.resolution => const Color(0xE64338CA),
        MediaTechnicalBadgeKind.dolbyVision => const Color(0xE66D28D9),
        MediaTechnicalBadgeKind.hdr => const Color(0xE69A3412),
        MediaTechnicalBadgeKind.dolbyAtmos => const Color(0xE6036991),
      };
}
```

- [ ] **Step 4：运行完整卡片组件测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart`

Expected: PASS，现有悬停、圆角、焦点测试不变。

```powershell
git add lib/features/library/presentation/immersive_media_card.dart test/library_presentation_components_test.dart
git commit -m "功能：在海报左上显示技术标签"
```

## Task 3：本地、网盘和分类海报接入汇总标签

**Files:**
- Modify: `lib/features/library/application/media_card_info.dart`
- Modify: `lib/features/library/application/library_media_view_data_builder.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_card_view_data.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/features/library/presentation/media_category_page.dart`
- Modify: `test/unified_media_card_info_test.dart`
- Modify: `test/cloud_resource_card_view_data_test.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：先写统一卡片汇总失败测试**

在 `test/unified_media_card_info_test.dart` 的本地与网盘系列数据中，把文件名改为 `S01E01.1080p.HDR.mkv` 和 `S01E02.2160p.DV.Atmos.mkv`，断言：

```dart
expect(
  localInfo.technicalBadges.map((badge) => badge.label),
  ['4K', '杜比视界', 'HDR', '杜比全景声'],
);
expect(
  cloudInfo.technicalBadges.map((badge) => badge.label),
  ['4K', '杜比视界', 'HDR', '杜比全景声'],
);
```

- [ ] **Step 2：运行测试并确认 `technicalBadges` 不存在**

Run: `D:\flutter\bin\flutter.bat test test\unified_media_card_info_test.dart`

Expected: FAIL，`UnifiedMediaCardInfo.technicalBadges` 未定义。

- [ ] **Step 3：给统一卡片信息增加汇总字段**

```dart
UnifiedMediaCardInfo({
  required this.title,
  required this.subtitle,
  required this.details,
  required List<ImmersiveMediaCardBadge> badges,
  required List<MediaTechnicalBadge> technicalBadges,
})  : badges = List.unmodifiable(badges),
      technicalBadges = List.unmodifiable(technicalBadges);

final List<MediaTechnicalBadge> technicalBadges;
```

在 `forSeries` 中使用：

```dart
const resolver = MediaTechnicalBadgeResolver();
final technicalBadges = resolver.aggregate([
  for (final episode in episodes)
    resolver.resolve(
      names: [episode.name, if (episode.remotePath != null) episode.remotePath!],
      resolution: episode.localItem?.resolution,
      videoWidth: episode.localItem?.videoWidth,
      videoHeight: episode.localItem?.videoHeight,
    ),
]);
```

`forLocalGroup` 新增 `required List<MediaTechnicalBadge> technicalBadges`，在重建返回值时原样传递。`LibraryMediaViewDataBuilder.build` 使用 `group.episodes` 调用 resolver 汇总后传入。

- [ ] **Step 4：运行统一信息和本地视图数据测试**

Run: `D:\flutter\bin\flutter.bat test test\unified_media_card_info_test.dart test\library_media_view_data_builder_test.dart`

Expected: PASS。

- [ ] **Step 5：先写三类海报接线失败断言**

分别在现有本地网格、网盘海报墙和分类页组件测试的 fixture 文件名中加入 `2160p.DV.Atmos`，断言对应 `ImmersiveMediaCard.technicalBadges`：

```dart
final card = tester.widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard).first);
expect(
  card.technicalBadges.map((badge) => badge.label),
  ['4K', '杜比视界', '杜比全景声'],
);
```

- [ ] **Step 6：运行三个测试并确认接线缺失**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart test\media_category_page_test.dart`

Expected: FAIL，卡片收到空技术标签。

- [ ] **Step 7：把汇总字段传到所有海报卡片**

- `LibraryMediaItemViewData` 增加 `technicalBadges`，`LibraryMediaViewDataBuilder` 从 `unified.technicalBadges` 赋值，`_LibraryMediaTileState` 传给 `ImmersiveMediaCard`。
- `CloudResourceCardViewData` 增加 `technicalBadges`，两个 factory 从 `unified.technicalBadges` 赋值，`CloudResourcePosterWall` 传给 `ImmersiveMediaCard`。
- `media_category_page.dart` 已使用 `UnifiedMediaCardInfoBuilder.forSeries`，将 `info.technicalBadges` 传给 `ImmersiveMediaCard`。

各接线点使用相同一行：

```dart
technicalBadges: technicalBadges,
```

或：

```dart
technicalBadges: unified.technicalBadges,
```

- [ ] **Step 8：运行海报相关测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\unified_media_card_info_test.dart test\library_media_view_data_builder_test.dart test\library_presentation_components_test.dart test\cloud_resource_card_view_data_test.dart test\cloud_resources_page_test.dart test\media_category_page_test.dart`

Expected: PASS。

```powershell
git add lib/features/library/application/media_card_info.dart lib/features/library/application/library_media_view_data_builder.dart lib/features/library/presentation/library_media_grid.dart lib/pages/cloud/resources/cloud_resource_card_view_data.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/features/library/presentation/media_category_page.dart test/unified_media_card_info_test.dart test/library_media_view_data_builder_test.dart test/library_presentation_components_test.dart test/cloud_resource_card_view_data_test.dart test/cloud_resources_page_test.dart test/media_category_page_test.dart
git commit -m "功能：统一海报技术标签"
```

## Task 4：所有播放前选集和版本界面接入 B 布局

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `lib/pages/local/local_series_detail_page.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Modify: `lib/features/library/presentation/media_category_page.dart`
- Modify: `lib/features/library/presentation/media_library_details_dialog.dart`
- Modify: `test/cloud_resource_episode_sheet_test.dart`
- Modify: `test/library_presentation_components_test.dart`
- Create: `test/media_technical_badge_surface_contract_test.dart`

- [ ] **Step 1：先写网盘和分类选集失败测试**

把测试视频名设置为 `示例.S01E01.2160p.DV.Atmos.mkv`，打开选集后断言：

```dart
expect(find.text('4K'), findsOneWidget);
expect(find.text('杜比视界'), findsOneWidget);
expect(find.text('杜比全景声'), findsOneWidget);
final title = tester.getRect(find.textContaining('示例 S01E01'));
final badges = tester.getRect(find.text('4K'));
expect(badges.top, greaterThan(title.bottom));
```

分类页选集测试明确断言：

```dart
expect(find.text('4K'), findsOneWidget);
expect(find.text('杜比视界'), findsOneWidget);
expect(find.text('杜比全景声'), findsOneWidget);
await tester.tap(find.textContaining('示例 S01E01'));
await tester.pumpAndSettle();
expect(selected?.name, contains('S01E01'));
```

- [ ] **Step 2：运行测试并确认标签不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_episode_sheet_test.dart test\library_presentation_components_test.dart`

Expected: FAIL，找不到 `4K`。

- [ ] **Step 3：网盘与分类选集使用共享标签行**

每个条目先解析自身：

```dart
final technicalBadges = const MediaTechnicalBadgeResolver().resolve(
  names: [video.name, video.remotePath],
);
```

网盘条目先定义 `final detailsText = _formatBytes(video.size);`；分类条目定义：

```dart
final detailsText = episode.sourceKind == MediaSourceKind.local
    ? episode.localItem?.path ?? ''
    : episode.remotePath ?? '';
```

然后把现有单一 `subtitle: Text(...)` 改为 B 布局：

```dart
subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    if (technicalBadges.isNotEmpty) ...[
      const SizedBox(height: 5),
      MediaTechnicalBadgeRow(badges: technicalBadges),
    ],
    const SizedBox(height: 4),
    Text(
      detailsText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ],
),
```

分类页以 `episode.name` 和 `episode.remotePath/localItem.path` 为 names，并传本地宽高和显式分辨率。

- [ ] **Step 4：运行网盘与分类选集测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_episode_sheet_test.dart test\library_presentation_components_test.dart`

Expected: PASS，TV 焦点和选集返回测试仍通过。

- [ ] **Step 5：先写所有选集入口共享组件的失败契约测试**

创建 `test/media_technical_badge_surface_contract_test.dart`，确保用户要求的每个入口都接入同一个解析器和组件：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('所有选集和版本入口复用技术标签解析器与标签行', () {
    const paths = <String>[
      'lib/pages/cloud/resources/cloud_resource_episode_sheet.dart',
      'lib/pages/local/local_series_detail_page.dart',
      'lib/pages/local/library_sheet.dart',
      'lib/features/library/presentation/media_category_page.dart',
      'lib/features/library/presentation/media_library_details_dialog.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('MediaTechnicalBadgeResolver'), reason: path);
      expect(source, contains('MediaTechnicalBadgeRow'), reason: path);
    }
  });
}
```

- [ ] **Step 6：运行新测试并确认本地和详情入口尚未接线**

Run: `D:\flutter\bin\flutter.bat test test\media_technical_badge_surface_contract_test.dart`

Expected: FAIL，至少本地剧集详情、经典本地选集和媒体详情缺少共享解析器或标签行。

- [ ] **Step 7：本地入口和详情使用同一 B 布局**

每个 `LocalMediaIndexItem` 使用：

```dart
final badges = const MediaTechnicalBadgeResolver().resolve(
  names: [episode.name, episode.path],
  resolution: episode.resolution,
  videoWidth: episode.videoWidth,
  videoHeight: episode.videoHeight,
);
```

每个 `MediaLibraryEpisode` 使用：

```dart
final local = episode.localItem;
final badges = const MediaTechnicalBadgeResolver().resolve(
  names: [
    episode.name,
    if (local != null) local.path,
    if (episode.remotePath != null) episode.remotePath!,
  ],
  resolution: local?.resolution,
  videoWidth: local?.videoWidth,
  videoHeight: local?.videoHeight,
);
```

在标题下方用 `MediaTechnicalBadgeRow`，其后保留原大小、字幕、路径和操作菜单；不改变 `onTap`、`TvEpisodeTileSurface` 或焦点结构。

- [ ] **Step 8：运行全部播放前选集测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_episode_sheet_test.dart test\library_presentation_components_test.dart test\media_category_page_test.dart test\media_technical_badge_surface_contract_test.dart`

Expected: PASS。

```powershell
git add lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/local/local_series_detail_page.dart lib/pages/local/library_sheet.dart lib/features/library/presentation/media_category_page.dart lib/features/library/presentation/media_library_details_dialog.dart test/cloud_resource_episode_sheet_test.dart test/library_presentation_components_test.dart test/media_category_page_test.dart test/media_technical_badge_surface_contract_test.dart
git commit -m "功能：为所有选集显示技术标签"
```

## Task 5：播放器右侧选集接入标签

**Files:**
- Modify: `lib/pages/video/video_page.dart`
- Modify: `test/local_video_controller_test.dart`

- [ ] **Step 1：先写播放器选集失败测试**

构造 `Road` 时让 `data` 包含 `D:/Media/E01.2160p.DV.Atmos.mkv`，`identifier` 保持普通中文集名；打开播放器选集面板并断言：

```dart
expect(find.text('4K'), findsOneWidget);
expect(find.text('杜比视界'), findsOneWidget);
expect(find.text('杜比全景声'), findsOneWidget);
expect(find.byType(TvEpisodeTileSurface), findsWidgets);
```

- [ ] **Step 2：运行测试并确认标签缺失**

Run: `D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart --plain-name "播放器选集显示当前文件技术标签"`

Expected: FAIL，找不到 `4K`。

- [ ] **Step 3：在播放器现有 `_EpisodeMenuItem` 上即时解析路径**

不扩充 `Road`，直接复用其中已存在的真实本地路径或网盘远程路径：

```dart
final technicalBadges = const MediaTechnicalBadgeResolver().resolve(
  names: [item.title, item.url],
);
```

把 `_buildEpisodeMenuTile` 中现有标题 `Text` 改为：

```dart
Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item.title,
        softWrap: true,
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: titleColor,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      if (technicalBadges.isNotEmpty) ...[
        const SizedBox(height: 6),
        MediaTechnicalBadgeRow(badges: technicalBadges),
      ],
    ],
  ),
),
```

保持当前集 GIF、选中背景、点击换集、TV 自动聚焦和滚动定位不变。

- [ ] **Step 4：运行播放器相关测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart test\tv_focus_surface_test.dart`

Expected: PASS。

```powershell
git add lib/pages/video/video_page.dart test/local_video_controller_test.dart
git commit -m "功能：为播放器选集显示技术标签"
```

## Task 6：版本、更新说明与发布前安装状态

**Files:**
- Modify: `pubspec.yaml`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1：在版本更新前记录当前 Windows 安装状态**

在 UTF-8 PowerShell 中运行并保存终端输出到本次交付记录，不写入仓库：

```powershell
chcp 65001
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$uninstallRoots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -eq '看影音' } |
  Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString
Get-AppxPackage | Where-Object {
  $_.Name -match 'kanyingyin' -or $_.PackageFamilyName -match 'kanyingyin'
} | Select-Object Name, Version, PackageFullName
$installedExe = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -eq '看影音' } |
  ForEach-Object { Join-Path $_.InstallLocation 'kanyingyin.exe' } |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1
if ($installedExe) {
  Get-Item -LiteralPath $installedExe |
    Select-Object FullName, @{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}
}
```

Expected: 明确记录 Inno 安装项、已安装 `kanyingyin.exe` 产品版本，以及旧 MSIX 是否存在；不能用 `pubspec.yaml` 代替。

- [ ] **Step 2：先更新版本历史测试为 2.1.169 并确认失败**

把 `test/version_history_current_test.dart` 当前 Windows 版本断言改为 `2.1.169`，并断言更新内容包含 `4K`、`杜比视界`、`选集`。

Run: `D:\flutter\bin\flutter.bat test test\version_history_current_test.dart`

Expected: FAIL，当前历史仍为 2.1.168。

- [ ] **Step 3：同步版本和普通用户文案**

- `pubspec.yaml`：`version: 2.1.169+20169`
- `pubspec.yaml` 历史兼容配置同步为 `msix_version: 2.1.169.0`，但不运行 MSIX 打包。
- `RELEASE_NOTES.md` 顶部新增 `2.1.169+20169`，说明封面常驻最高规格标签、每个选集显示自身规格、不修改用户原始文件。
- `lib/utils/version_history.dart` Windows 历史首项新增 `2.1.169`、日期 `2026-08-24`，使用相同用户文案。
- 保留 Android 当前交付版 `2.1.160`，本轮不打包 Android，不触发 TV 流程。

- [ ] **Step 4：运行版本测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\version_history_current_test.dart test\release_config_contract_test.dart`

Expected: PASS。

```powershell
git add pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart test/version_history_current_test.dart
git commit -m "发布：更新媒体技术标签测试版至2.1.169"
```

## Task 7：完整验证、Windows 安装程序和最终提交状态

**Files:**
- Verify only unless a relevant failure requires a scoped fix.

- [ ] **Step 1：格式化本轮 Dart 文件并检查工作区**

Run: `D:\flutter\bin\dart.bat format lib\features\library\application\media_technical_badges.dart lib\features\library\application\media_card_info.dart lib\features\library\application\library_media_view_data_builder.dart lib\features\library\presentation\immersive_media_card.dart lib\features\library\presentation\library_media_grid.dart lib\features\library\presentation\media_category_page.dart lib\features\library\presentation\media_library_details_dialog.dart lib\pages\cloud\resources\cloud_resource_card_view_data.dart lib\pages\cloud\resources\cloud_resource_poster_wall.dart lib\pages\cloud\resources\cloud_resource_episode_sheet.dart lib\pages\local\local_series_detail_page.dart lib\pages\local\library_sheet.dart lib\pages\video\video_page.dart test\media_technical_badges_test.dart test\unified_media_card_info_test.dart test\library_presentation_components_test.dart test\cloud_resource_card_view_data_test.dart test\cloud_resources_page_test.dart test\cloud_resource_episode_sheet_test.dart test\media_category_page_test.dart test\media_technical_badge_surface_contract_test.dart test\local_video_controller_test.dart test\version_history_current_test.dart`

Expected: 只格式化本轮文件。

Run: `git status --short` and `git diff --check`

Expected: 无空白错误；没有无关修改。

- [ ] **Step 2：运行聚焦测试**

Run: `D:\flutter\bin\flutter.bat test test\media_technical_badges_test.dart test\unified_media_card_info_test.dart test\library_presentation_components_test.dart test\cloud_resource_card_view_data_test.dart test\cloud_resources_page_test.dart test\cloud_resource_episode_sheet_test.dart test\media_category_page_test.dart test\media_technical_badge_surface_contract_test.dart test\local_video_controller_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 3：运行完整质量门**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 全部测试 PASS。

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`

- [ ] **Step 4：锁定依赖并构建/打包 Windows EXE**

Run: `D:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile`

Expected: 成功且不修改锁文件。

Run: `powershell -ExecutionPolicy Bypass -File .\tool\windows\build_exe_release.ps1`

Expected: Windows Release 构建和 Inno Setup 编译成功；桌面生成唯一的 `看影音-2.1.169-测试版-安装程序.exe`；脚本输出 Release 主程序版本、安装器版本、大小、SHA-256 和 Authenticode 状态。不得运行 Android TV 构建、`tvTest`、TV 标签或 TV Release 流程。

- [ ] **Step 5：再次独立核对构建产物**

```powershell
$release = Get-Item '.\build\windows\x64\runner\Release\kanyingyin.exe'
$installer = Get-Item "$env:USERPROFILE\Desktop\看影音-2.1.169-测试版-安装程序.exe"
$release | Select-Object FullName, Length, @{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}, LastWriteTime
$installer | Select-Object FullName, Length, @{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}, LastWriteTime
Get-FileHash -LiteralPath $release.FullName -Algorithm SHA256
Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
Get-AuthenticodeSignature -LiteralPath $installer.FullName | Select-Object Status, StatusMessage
```

Expected: 两个产品版本均为 2.1.169，文件非空且为本轮新生成；记录两份 SHA-256。未要求安装，因此不要把“安装器已生成”报告成“已安装验证”。

- [ ] **Step 6：检查并提交验证过程中产生的相关修改**

Run: `git status --short`

若格式化或修复产生尚未提交的本轮改动：

```powershell
git diff --check
git add lib/features/library/application/media_technical_badges.dart lib/features/library/application/media_card_info.dart lib/features/library/application/library_media_view_data_builder.dart lib/features/library/presentation/immersive_media_card.dart lib/features/library/presentation/library_media_grid.dart lib/features/library/presentation/media_category_page.dart lib/features/library/presentation/media_library_details_dialog.dart lib/pages/cloud/resources/cloud_resource_card_view_data.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/local/local_series_detail_page.dart lib/pages/local/library_sheet.dart lib/pages/video/video_page.dart test/media_technical_badges_test.dart test/unified_media_card_info_test.dart test/library_media_view_data_builder_test.dart test/library_presentation_components_test.dart test/cloud_resource_card_view_data_test.dart test/cloud_resources_page_test.dart test/cloud_resource_episode_sheet_test.dart test/media_category_page_test.dart test/media_technical_badge_surface_contract_test.dart test/local_video_controller_test.dart test/version_history_current_test.dart pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
git diff --cached --check
git commit -m "测试：完成媒体技术标签交付验证"
```

Expected: 不提交无关改动，不提交 `.superpowers` 可视化临时文件或构建产物。

- [ ] **Step 7：最终 Git 状态与交付报告**

Run: `git status --short; git log -7 --oneline`

Expected: 工作区无本轮未提交改动；报告聚焦测试、完整测试、静态分析、Windows Release、安装器路径/版本/大小/SHA-256/签名状态，以及“未执行安装运行验收”。
