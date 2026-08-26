# 海报封面统一规范与深色白边修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 修复深色模式下《怪奇物语》第 2～5 季海报白线，并让所有现役封面入口共享 2:3 比例、主题裁边和中性占位规则。

**Architecture:** 新增一个无状态 PosterCover 显示层，只负责主题裁边和占位，不加载文件、不请求网络、不保存状态。CloudPosterImage 与各页面保留现有图片来源和回退顺序，在最外层复用 PosterCover；父布局继续负责尺寸。

**Tech Stack:** Flutter 3.41.9、Dart、flutter_test、现有 TmdbNetworkImage、PowerShell 7、Windows Release、Inno Setup 6。

**设计依据:** docs/superpowers/specs/2026-08-25-poster-cover-standardization-design.md

**提交策略:** 按项目约束不执行 git commit；每个任务完成后只检查 git diff 与测试结果，并保留无关工作区修改。

---

## 文件结构

**新增**

- lib/widgets/poster_cover.dart：唯一共享封面显示规则，包含 2:3 常量、深色 1.06 裁边和中性占位。
- test/poster_cover_test.dart：共享显示层的主题、裁边和占位测试。
- test/poster_cover_layout_contract_test.dart：所有入口比例、尺寸和共享占位接入的集中契约测试。

**修改**

- lib/widgets/cloud_poster_image.dart：保留缓存与网络回退，改用 PosterCover，移除云端专用占位实现。
- test/cloud_poster_image_test.dart：保留真实像素回归，增加浅色模式与共享层接入验证。
- lib/features/library/presentation/library_media_grid.dart：主媒体墙精确 2:3，真实图片和占位接入共享层。
- lib/pages/cloud/resources/cloud_resource_poster_wall.dart：网盘墙精确 2:3，预热计算同步比例。
- lib/features/library/presentation/media_category_page.dart：分类墙精确 2:3，图片与占位接入共享层。
- lib/pages/cloud/resources/cloud_resource_episode_sheet.dart：季度海报保留 92×138，统一占位。
- lib/features/history/presentation/history_page.dart：历史封面改为 60×90，并统一本地、网络、网盘显示。
- lib/pages/tmdb_match_dialog.dart：候选封面改为 56×84，并统一无图和失败状态。
- lib/pages/local/library_sheet.dart：小图改为 40×60，并统一本地与网络回退显示。
- RELEASE_NOTES.md、UPDATE_DIALOG_COPY.md、lib/utils/version_history.dart：补充系统统一封面的用户文案。
- 已有版本文件与契约测试：只核对 2.1.178+20178 一致性，不重复改写已经正确的内容。

---

### Task 1: 建立最小共享封面显示层

**Files:**

- Create: lib/widgets/poster_cover.dart
- Create: test/poster_cover_test.dart

- [ ] **Step 1: 写共享规则失败测试**

创建 test/poster_cover_test.dart：

~~~dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/widgets/poster_cover.dart';

void main() {
  test('封面比例和深色裁边量固定', () {
    expect(posterAspectRatio, 2 / 3);
    expect(posterDarkScale, 1.06);
  });

  testWidgets('浅色模式不放大真实海报', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const PosterCover(
          child: SizedBox(key: ValueKey<String>('poster-image')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('poster-image')), findsOneWidget);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('深色模式居中放大并裁切真实海报', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const PosterCover(
          child: SizedBox(key: ValueKey<String>('poster-image')),
        ),
      ),
    );

    final transform = tester.widget<Transform>(find.byType(Transform));
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1.06, 0.0001));
    expect(find.byType(ClipRect), findsOneWidget);
  });

  testWidgets('无图统一使用中性影片占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const SizedBox(
          width: 60,
          height: 90,
          child: PosterCover.placeholder(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('poster-cover-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });
}
~~~

- [ ] **Step 2: 运行测试并确认 RED**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_test.dart
~~~

Expected: FAIL，提示 widgets/poster_cover.dart 或 PosterCover 不存在。

- [ ] **Step 3: 写最小实现**

创建 lib/widgets/poster_cover.dart：

~~~dart
import 'package:flutter/material.dart';

const double posterAspectRatio = 2 / 3;
const double posterDarkScale = 1.06;

class PosterCover extends StatelessWidget {
  const PosterCover({
    super.key,
    required this.child,
  });

  const PosterCover.placeholder({super.key}) : child = null;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final image = child;
    if (image == null) {
      final colors = Theme.of(context).colorScheme;
      return ColoredBox(
        key: const ValueKey<String>('poster-cover-placeholder'),
        color: colors.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            size: 32,
            color: colors.outline,
          ),
        ),
      );
    }
    if (Theme.of(context).brightness != Brightness.dark) return image;
    return ClipRect(
      child: Transform.scale(
        scale: posterDarkScale,
        child: image,
      ),
    );
  }
}
~~~

- [ ] **Step 4: 运行测试并确认 GREEN**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_test.dart
~~~

Expected: PASS，4 项测试通过。

- [ ] **Step 5: 检查本任务差异**

Run:

~~~powershell
git diff --check -- lib/widgets/poster_cover.dart test/poster_cover_test.dart
git status --short
~~~

Expected: 无空白错误；只新增两个文件，原有无关修改仍保留。

---

### Task 2: 让 CloudPosterImage 复用共享层

**Files:**

- Modify: lib/widgets/cloud_poster_image.dart
- Modify: test/cloud_poster_image_test.dart

- [ ] **Step 1: 写共享层接入和浅色回归测试**

在 test/cloud_poster_image_test.dart 导入 poster_cover.dart，并在现有深色像素测试之后加入：

~~~dart
  testWidgets('网盘海报通过共享封面层渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: CloudPosterImage(
          cachePath: null,
          url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
          bytesLoader: (_) async => _pngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PosterCover), findsOneWidget);
  });

  testWidgets('浅色模式不应用海报边缘放大', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: CloudPosterImage(
          cachePath: null,
          url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
          bytesLoader: (_) async => _pngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PosterCover), findsOneWidget);
    expect(find.byType(Transform), findsNothing);
  });
~~~

同时把已有占位键 cloud-poster-placeholder 改为 poster-cover-placeholder。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\cloud_poster_image_test.dart
~~~

Expected: FAIL，“网盘海报通过共享封面层渲染”找不到 PosterCover。

- [ ] **Step 3: 替换云端专用裁边和占位**

在 lib/widgets/cloud_poster_image.dart 导入 poster_cover.dart。把 _cropPosterEdge 的两个调用改为：

~~~dart
return PosterCover(child: child);
~~~

和：

~~~dart
return PosterCover(
  child: TmdbNetworkImage(
    url: url,
    bytesLoader: widget.bytesLoader,
    fit: widget.fit,
    width: widget.width,
    height: widget.height,
    cacheWidth: widget.cacheWidth,
    cacheHeight: widget.cacheHeight,
    filterQuality: widget.filterQuality,
    loadingBuilder: _placeholder,
    errorBuilder: (context, _, __) => _placeholder(context),
  ),
);
~~~

删除 _cropPosterEdge 方法与 CloudPosterPlaceholder 类。默认占位改为：

~~~dart
  Widget _placeholder(BuildContext context) =>
      widget.placeholderBuilder?.call(context) ??
      const PosterCover.placeholder();
~~~

暂时保留 placeholderBuilder 参数，等所有调用点迁移完再删除，避免任务中间破坏编译。

- [ ] **Step 4: 运行云海报测试并确认 GREEN**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_test.dart test\cloud_poster_image_test.dart
~~~

Expected: PASS；深色真实像素边缘测试、浅色无 Transform、缓存优先和状态保留全部通过。

---

### Task 3: 统一主海报墙和分类页

**Files:**

- Create: test/poster_cover_layout_contract_test.dart
- Modify: lib/features/library/presentation/library_media_grid.dart
- Modify: lib/pages/cloud/resources/cloud_resource_poster_wall.dart
- Modify: lib/features/library/presentation/media_category_page.dart

- [ ] **Step 1: 写网格比例失败契约**

创建 test/poster_cover_layout_contract_test.dart：

~~~dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> _source(String path) => File(path).readAsString();

void main() {
  test('所有通用海报墙使用精确 2 比 3 比例', () async {
    final library = await _source(
      'lib/features/library/presentation/library_media_grid.dart',
    );
    final cloud = await _source(
      'lib/pages/cloud/resources/cloud_resource_poster_wall.dart',
    );
    final category = await _source(
      'lib/features/library/presentation/media_category_page.dart',
    );

    expect(
      RegExp('fallbackChildAspectRatio: posterAspectRatio')
          .allMatches(library),
      hasLength(2),
    );
    expect(
      RegExp('childAspectRatio: posterAspectRatio').allMatches(cloud),
      hasLength(2),
    );
    expect(
      RegExp('posterAspectRatio').allMatches(category).length,
      greaterThanOrEqualTo(2),
    );
    expect('$library$cloud$category', isNot(contains('0.68')));
  });
}
~~~

- [ ] **Step 2: 运行契约并确认 RED**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_layout_contract_test.dart
~~~

Expected: FAIL，三个入口仍包含 0.68。

- [ ] **Step 3: 把三个通用网格改为共享比例**

三个文件导入 poster_cover.dart，并完成以下机械替换：

~~~dart
fallbackChildAspectRatio: posterAspectRatio,
~~~

替换 library_media_grid.dart 的两处 0.68、cloud_resource_poster_wall.dart 的网格 0.68、media_category_page.dart 的网格 0.68。

cloud_resource_poster_wall.dart 和 media_category_page.dart 的预热计算同步改为：

~~~dart
childAspectRatio: posterAspectRatio,
~~~

不得修改 lib/features/tv/presentation/tv_layout_policy.dart 中 Android TV 专用 0.78。

- [ ] **Step 4: 让本地主墙与分类页真实图片接入 PosterCover**

library_media_grid.dart 的 _cover 返回值改为：

~~~dart
    return PosterCover(
      child: LibraryMediaCoverFallback.build(
        widget.item,
        placeholderBuilder: (_) => const PosterCover.placeholder(),
        decodeSize: widget.decodeSize,
        bytesLoader: widget.networkImageLoader,
      ),
    );
~~~

删除原有 primaryContainer、圆形装饰和 play_circle/video_collection 占位。

media_category_page.dart 保持现有缓存优先和网络回退分支，但所有 Image.file 与 TmdbNetworkImage 返回值用 PosterCover(child: ...) 包裹；无图和最终失败统一返回：

~~~dart
const PosterCover.placeholder()
~~~

云来源继续使用 CloudPosterImage，本任务不改变其缓存与网络参数。

- [ ] **Step 5: 运行聚焦测试**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_layout_contract_test.dart test\library_presentation_components_test.dart test\media_category_page_test.dart test\cloud_resources_page_test.dart
~~~

Expected: PASS；通用网格无 0.68，TV 既有布局测试不变。

---

### Task 4: 统一季度、历史、TMDB 候选和小图

**Files:**

- Modify: test/poster_cover_layout_contract_test.dart
- Modify: test/cloud_resource_episode_sheet_test.dart
- Modify: test/tmdb_match_dialog_test.dart
- Modify: lib/pages/cloud/resources/cloud_resource_episode_sheet.dart
- Modify: lib/pages/cloud/resources/cloud_resource_poster_wall.dart
- Modify: lib/features/library/presentation/media_category_page.dart
- Modify: lib/features/history/presentation/history_page.dart
- Modify: lib/pages/tmdb_match_dialog.dart
- Modify: lib/pages/local/library_sheet.dart
- Modify: lib/widgets/cloud_poster_image.dart

- [ ] **Step 1: 扩充固定尺寸失败契约**

在 poster_cover_layout_contract_test.dart 增加：

~~~dart
  test('紧凑封面入口使用统一 2 比 3 尺寸', () async {
    final history = await _source(
      'lib/features/history/presentation/history_page.dart',
    );
    final tmdb = await _source('lib/pages/tmdb_match_dialog.dart');
    final local = await _source('lib/pages/local/library_sheet.dart');
    final season = await _source(
      'lib/pages/cloud/resources/cloud_resource_episode_sheet.dart',
    );

    expect(history, contains('width: 60,'));
    expect(history, contains('height: 90,'));
    expect(tmdb, contains('width: 56,'));
    expect(tmdb, contains('height: 84,'));
    expect(local, contains('width: 40,'));
    expect(
      RegExp('height: 60,').allMatches(local).length,
      greaterThanOrEqualTo(3),
    );
    expect(season, contains('width: 92,'));
    expect(season, contains('height: 138,'));
  });

  test('封面失败状态不再使用彩色圆形或损坏图片图标', () async {
    final sources = await Future.wait([
      _source('lib/features/library/presentation/library_media_grid.dart'),
      _source('lib/features/library/presentation/media_category_page.dart'),
      _source('lib/features/history/presentation/history_page.dart'),
      _source('lib/pages/tmdb_match_dialog.dart'),
      _source('lib/pages/local/library_sheet.dart'),
    ]);
    final joined = sources.join();

    expect(joined, isNot(contains('Icons.broken_image_outlined')));
    expect(joined, isNot(contains('Icons.movie_creation_outlined')));
    expect(joined, contains('PosterCover.placeholder'));
  });
~~~

在 cloud_resource_episode_sheet_test.dart 的首个测试中增加：

~~~dart
    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('cloud-season-poster-1')),
      ),
      const Size(92, 138),
    );
~~~

在 tmdb_match_dialog_test.dart 首个成功搜索测试中，选择候选前增加：

~~~dart
    final candidatePoster = find.byKey(
      const ValueKey<String>('tmdb-candidate-poster-42'),
    );
    expect(tester.getSize(candidatePoster), const Size(56, 84));
~~~

- [ ] **Step 2: 运行测试并确认 RED**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_layout_contract_test.dart test\cloud_resource_episode_sheet_test.dart test\tmdb_match_dialog_test.dart
~~~

Expected: FAIL；历史、TMDB 和小图仍是旧尺寸，TMDB 候选尚无稳定键。

- [ ] **Step 3: 修改固定尺寸并接入共享显示**

history_page.dart：

~~~dart
leading: SizedBox(
  width: 60,
  height: 90,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: _Poster(entry: entry),
  ),
),
~~~

本地 Image.file 与 TmdbNetworkImage 用 PosterCover(child: ...) 包裹；无图和错误返回 const PosterCover.placeholder()。云分支继续使用 CloudPosterImage，不再传专用 placeholderBuilder。

tmdb_match_dialog.dart：

~~~dart
SizedBox(
  key: ValueKey<String>(
    'tmdb-candidate-poster-' + metadata.id.toString(),
  ),
  width: 56,
  height: 84,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: poster == null
        ? const PosterCover.placeholder()
        : PosterCover(
            child: TmdbNetworkImage(
              url: poster,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const PosterCover.placeholder(),
            ),
          ),
  ),
),
~~~

library_sheet.dart 保持 remoteUrl 优先、本地 cover 回退的顺序，把全部 height: 56 改为 height: 60；TmdbNetworkImage 与 Image.file 用 PosterCover(child: ...) 包裹，最终失败和无图返回 const PosterCover.placeholder()。

cloud_resource_episode_sheet.dart 保持 92×138 和 9px 圆角，只移除 CloudPosterImage 的 placeholderBuilder 参数以及仅供该参数使用的 _placeholder 方法。

cloud_resource_poster_wall.dart 从 CloudPosterImage 调用中移除 placeholderBuilder: _mediaPlaceholder，并删除只被该参数使用的 _mediaPlaceholder 方法；卡片文字、技术标签和菜单不变。

media_category_page.dart 的云来源 CloudPosterImage 不再传 placeholderBuilder；本地与网络分支统一使用 PosterCover.placeholder，因此删除函数内原有彩色 placeholder 闭包。

- [ ] **Step 4: 清理 CloudPosterImage 的旧占位扩展点**

确认所有 CloudPosterImage 调用点都不再传 placeholderBuilder 后，从构造函数与字段中删除：

~~~dart
this.placeholderBuilder,
final WidgetBuilder? placeholderBuilder;
~~~

_placeholder 简化为：

~~~dart
Widget _placeholder(BuildContext _) =>
    const PosterCover.placeholder();
~~~

运行：

~~~powershell
rg -n "placeholderBuilder:" lib | rg "cloud|history|media_category"
~~~

Expected: 不再存在 CloudPosterImage 的页面级专用占位传参；其他非海报组件的 placeholderBuilder 不受影响。

- [ ] **Step 5: 运行固定入口与现有行为测试**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\poster_cover_test.dart test\cloud_poster_image_test.dart test\poster_cover_layout_contract_test.dart test\cloud_resource_episode_sheet_test.dart test\history_cloud_poster_contract_test.dart test\tmdb_match_dialog_test.dart test\library_presentation_components_test.dart test\media_category_page_test.dart
~~~

Expected: PASS；现有缓存优先、候选选择、季度回退、历史网盘分支和卡片交互测试仍通过。

---

### Task 5: 更新 2.1.178 用户文案并核对版本契约

**Files:**

- Modify: RELEASE_NOTES.md
- Modify: UPDATE_DIALOG_COPY.md
- Modify: lib/utils/version_history.dart
- Verify: pubspec.yaml
- Verify: lib/core/app_version.dart
- Verify: android/app/build.gradle.kts
- Verify: tool/android/build_signed_release.ps1
- Test: test/release_config_contract_test.dart
- Test: test/version_consistency_test.dart
- Test: test/version_history_current_test.dart

- [ ] **Step 1: 将 2.1.178 文案扩展为最终用户范围**

RELEASE_NOTES.md、UPDATE_DIALOG_COPY.md 和 version_history.dart 的 2.1.178 更新点统一为：

~~~text
- 修复《怪奇物语》第 2～5 季等原图自带较宽白框的海报，在深色模式下不再残留左右白线。
- 本地媒体库、个人网盘、播放历史和 TMDB 匹配等封面统一为 2:3，作品构图在不同入口保持一致。
- 无海报、加载中或加载失败时统一显示简洁的影片占位，不再混用彩色装饰和损坏图片图标。
- Android 手机本轮不打包；Android TV 继续暂停。
- 本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存。
~~~

不得把当前测试版文案改成正式版，也不得加入 Android TV 交付说明。

- [ ] **Step 2: 运行版本契约**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\release_config_contract_test.dart test\version_consistency_test.dart test\version_history_current_test.dart
~~~

Expected: PASS；所有版本源均为 2.1.178+20178，当前历史条目日期为 2026-08-25。

- [ ] **Step 3: 检查本轮和无关差异边界**

Run:

~~~powershell
git status --short
git diff --check
git diff -- lib/widgets/poster_cover.dart lib/widgets/cloud_poster_image.dart lib/features/library/presentation/library_media_grid.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/features/library/presentation/media_category_page.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/features/history/presentation/history_page.dart lib/pages/tmdb_match_dialog.dart lib/pages/local/library_sheet.dart test/poster_cover_test.dart test/cloud_poster_image_test.dart test/poster_cover_layout_contract_test.dart test/cloud_resource_episode_sheet_test.dart test/tmdb_match_dialog_test.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart
~~~

Expected: 没有无关格式化；media_name_analyzer、media_technical_badges 及其测试的既有修改保持原样且不被回退。

---

### Task 6: 完整自动化、静态分析与对抗式复核

**Files:**

- Verify only: 全部本轮文件和完整测试套件

- [ ] **Step 1: 运行完整测试**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub
~~~

Expected: PASS；失败数 0。若出现 Windows 本地监听 errno 121，只重跑明确失败文件并按小批串行验证，不把未完成的全套测试报告为通过。

- [ ] **Step 2: 运行静态分析**

Run:

~~~powershell
& 'D:\flutter\bin\flutter.bat' analyze --no-pub
~~~

Expected: No issues found。

- [ ] **Step 3: 对抗式复核**

逐项检查：

- 深色裁切只应用真实海报，浅色无 1.06。
- 所有现役入口均为 2:3，TV 专用 0.78 未变。
- 各图片来源和回退顺序未被重排。
- 占位失败不抛异常，不影响扫描、索引和播放。
- 标题、技术标签、悬停、菜单、历史进度和 TMDB 选择行为未改。
- 未修改或写入 D:\看影音\缓存\cloud_posters 中的任何文件。
- 未生成 MSIX、Android 手机或 Android TV 产物。
- 未执行 git commit。

发现问题时先补最小回归测试，再修共享根因并重跑相关测试。

---

### Task 7: 构建、打包、安装与真实视觉验收

**Files/Artifacts:**

- Build: build/windows/x64/runner/Release/kanyingyin.exe
- Package: C:\Users\asus\Desktop\看影音-2.1.178-测试版-安装程序.exe
- Install target: D:\看影音\kanyingyin.exe

- [ ] **Step 1: 再次记录安装前状态**

Run:

~~~powershell
$installedExe = 'D:\看影音\kanyingyin.exe'
Get-AppxPackage -Name 'com.kanyingyin.player' | Select-Object Name,Version,InstallLocation
if (Test-Path -LiteralPath $installedExe) {
  Get-Item -LiteralPath $installedExe |
    Select-Object FullName,@{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}},Length,LastWriteTime
  Get-FileHash -LiteralPath $installedExe -Algorithm SHA256
}
~~~

Expected: 安装前 Inno 主程序仍为 2.1.177；旧 MSIX 不存在。若状态变化，记录实际值后继续，不能用 pubspec 推断。

- [ ] **Step 2: 构建 Windows Release 并生成 Inno Setup**

Run:

~~~powershell
& '.\tool\windows\build_exe_release.ps1'
~~~

Expected:

- flutter build windows --release --no-pub 成功。
- Release kanyingyin.exe ProductVersion 为 2.1.178。
- 桌面生成且仅生成一个本轮安装器。
- 安装器文件名为 看影音-2.1.178-测试版-安装程序.exe。
- 输出 Release 与安装器的大小、SHA-256、产品版本和签名状态。

- [ ] **Step 3: 独立核对产物**

Run:

~~~powershell
$releaseExe = 'D:\KanYingYin\build\windows\x64\runner\Release\kanyingyin.exe'
$installer = 'C:\Users\asus\Desktop\看影音-2.1.178-测试版-安装程序.exe'
Get-Item -LiteralPath $releaseExe,$installer |
  Select-Object FullName,@{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}},Length,LastWriteTime
Get-FileHash -LiteralPath $releaseExe,$installer -Algorithm SHA256
Get-AuthenticodeSignature -LiteralPath $installer |
  Select-Object Status,StatusMessage,SignerCertificate
~~~

Expected: 两个 ProductVersion 均以 2.1.178 开头，文件非空，哈希已记录；签名状态如实报告，不把 unsigned 说成 signed。

- [ ] **Step 4: 安装测试版并核对安装后版本**

关闭正在运行的看影音后，通过可见 Inno Setup 向导运行：

~~~powershell
$installer = 'C:\Users\asus\Desktop\看影音-2.1.178-测试版-安装程序.exe'
Start-Process -FilePath $installer -Wait
~~~

安装完成后：

~~~powershell
$installedExe = 'D:\看影音\kanyingyin.exe'
Get-Item -LiteralPath $installedExe |
  Select-Object FullName,@{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}},Length,LastWriteTime
Get-FileHash -LiteralPath $installedExe -Algorithm SHA256
~~~

Expected: 已安装 ProductVersion 为 2.1.178，并记录新哈希。若安装目录被用户改动，先从卸载注册表和快捷方式解析真实路径，再核对，不猜测。

- [ ] **Step 5: 启动已安装应用做真实视觉验收**

启动 D:\看影音\kanyingyin.exe，并在应用中执行：

1. 切换深色模式，打开《怪奇物语》季度海报墙。
2. 分别查看第 2、3、4、5 季左右边缘，确认没有白线。
3. 检查本地主海报墙、网盘海报墙、分类页、季度选集、播放历史、TMDB 候选和媒体库小图均为 2:3。
4. 触发至少一个无海报或加载失败状态，确认显示中性 movie_outlined 占位。
5. 切换浅色模式，确认真实海报不使用 1.06 放大。
6. 检查标题、评分、技术标签、悬停、菜单、播放进度和 TMDB 选择仍可用。

Expected: 所有视觉项通过。任一真实入口失败都停止“已解决”结论，记录截图与入口，回到对应任务补回归测试。

- [ ] **Step 6: 最终工作区与交付清单**

Run:

~~~powershell
git status --short
git diff --check
Get-Item -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.178-测试版-安装程序.exe' |
  Select-Object FullName,@{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}},Length,LastWriteTime
~~~

Expected: 桌面安装器存在；本轮文件、既有资源标签修改和未跟踪设计文档均如实列出；不执行 git add 或 git commit。
