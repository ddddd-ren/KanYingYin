# 网盘剧集强类型身份与本地海报墙统一实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 修复同一集不同网盘资源被显示为新集数的问题，并让本地海报墙在宽屏下保持 300 像素尺寸上限、自动增加列数，交付 2.1.22 签名 MSIX。

**Architecture:** 保留 CloudMediaIndexItem 作为季集识别事实来源，在资源集合生成的虚拟 CloudFileEntry 上附加可选的强类型季号、集号和版本标签；选集界面优先消费这些字段，真实路径解析只负责旧数据兼容。本地网格只替换布局委托，继续复用现有卡片、封面适配与交互实现。

**Tech Stack:** Flutter 3.41.9、Dart、Material GridView、flutter_test、Windows Release、msix 3.18.0、PowerShell。

---

## 文件结构

- lib/modules/cloud/cloud_file_entry.dart：为应用内虚拟网盘条目承载可选季号、集号和版本标签。
- lib/pages/cloud/resources/cloud_resource_collection.dart：从索引项生成虚拟条目时保留强类型身份和版本标签。
- lib/pages/cloud/resources/cloud_resource_episode_sheet.dart：优先使用强类型身份生成选集标签，并保留旧路径解析回退。
- lib/features/library/presentation/library_media_grid.dart：统一为最大 300 像素的自适应网格。
- test/cloud_resources_page_test.dart：覆盖纯数字真实文件名、同集多版本、唯一集数和选集行数。
- test/library_presentation_components_test.dart：覆盖 620、1320、1920 像素宽度下的列数和卡片宽度。
- pubspec.yaml、lib/core/app_version.dart：更新应用和 MSIX 版本。
- README.md、RELEASE_NOTES.md、UPDATE_DIALOG_COPY.md、lib/utils/version_history.dart：更新普通用户可见文案。
- test/version_consistency_test.dart、test/version_history_current_test.dart、test/identity_v2_zero_residue_test.dart：锁定 2.1.22 版本契约和更新说明。

### Task 1: 用失败测试复现同集不同资源的错误集号

**Files:**
- Modify: test/cloud_resources_page_test.dart

- [ ] **Step 1: 引入作品树类型并建立真实索引夹具**

增加 cloud_media_tree.dart 导入，并增加以下夹具。它生成第 3 季 6 个唯一集号、每集两个真实版本，共 12 个纯数字文件：

~~~dart
CloudResourceMediaGroup _indexedVariantMediaGroup() {
  const sourceId = 'source';
  const workKey = 'source|work|duplicate-episodes';
  const root = CloudFileEntry(
    id: 'duplicate-episodes',
    remotePath: '/影视/测试剧',
    name: '测试剧',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const work = CloudWorkIdentity(
    sourceId: sourceId,
    workKey: workKey,
    root: root,
    remoteName: '测试剧',
    displayTitle: '测试剧',
    titleCandidates: <String>['测试剧'],
    seasons: <CloudSeasonIdentity>[
      CloudSeasonIdentity(
        workKey: workKey,
        seasonNumber: 3,
        displayName: '测试剧 第 3 季',
        remoteDirectories: <CloudFileEntry>[],
        episodes: <CloudEpisodeIdentity>[],
      ),
    ],
  );
  final items = <CloudMediaIndexItem>[];
  for (var episode = 1; episode <= 6; episode++) {
    final token = episode.toString().padLeft(2, '0');
    for (final (id, folder, tags)
        in const <(String, String, MediaReleaseTags)>[
      (
        'web',
        '第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos',
        MediaReleaseTags(
          resolution: '2160p',
          source: 'WEB-DL',
          codec: 'H265',
          audio: <String>['DDP 5.1', 'Atmos'],
        ),
      ),
      (
        'dv',
        '第三季（2025）4K DV&HDR',
        MediaReleaseTags(
          resolution: '4K',
          dynamicRange: <String>['DV', 'HDR'],
        ),
      ),
    ]) {
      items.add(
        CloudMediaIndexItem(
          sourceId: sourceId,
          remoteId: '$id-$episode',
          remotePath: '/影视/测试剧/$folder/$token.mkv',
          name: '$token.mkv',
          remoteName: '$token.mkv',
          displayName: '测试剧 S03E$token.mkv',
          workKey: workKey,
          workRootId: root.id,
          workRootPath: root.remotePath,
          size: 1024,
          modifiedAt: null,
          seriesName: '测试剧',
          seasonNumber: 3,
          episodeNumber: episode,
          mediaType: CloudMediaType.episode,
          releaseTags: tags,
        ),
      );
    }
  }
  return CloudResourceCollectionGrouper()
      .group(
        items: items,
        works: const <CloudWorkIdentity>[work],
        query: '',
      )
      .groups
      .single;
}
~~~

- [ ] **Step 2: 写入选集行为回归测试**

~~~dart
testWidgets('不同资源的重复集号使用索引身份且保留全部版本', (tester) async {
  final group = _indexedVariantMediaGroup();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCloudResourceEpisodeSheet(
              context: context,
              sourceId: 'source',
              group: group,
            ),
            child: const Text('打开重复集号选集'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('打开重复集号选集'));
  await tester.pumpAndSettle();

  expect(group.uniqueEpisodeCount, 6);
  expect(group.videos, hasLength(12));
  expect(find.text('6 集'), findsNWidgets(2));
  expect(find.byType(ListTile), findsNWidgets(12));
  expect(
    find.text('S03E01 · 2160p WEB-DL H265 DDP 5.1 Atmos'),
    findsOneWidget,
  );
  expect(find.text('S03E01 · 4K DV HDR'), findsOneWidget);
  expect(find.textContaining('第 2 集'), findsNothing);
});
~~~

- [ ] **Step 3: 运行测试并确认正确失败**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/cloud_resources_page_test.dart --plain-name "不同资源的重复集号使用索引身份且保留全部版本"
~~~

Expected: FAIL；12 个视频和 6 个唯一集数已存在，但纯数字真实路径无法提供集号，第二个资源会出现“第 2 集”且找不到两个 S03E01 标签。

### Task 2: 贯通强类型季集身份并修复选集展示

**Files:**
- Modify: lib/modules/cloud/cloud_file_entry.dart
- Modify: lib/pages/cloud/resources/cloud_resource_collection.dart
- Modify: lib/pages/cloud/resources/cloud_resource_episode_sheet.dart
- Test: test/cloud_resources_page_test.dart
- Test: test/cloud_resource_collection_test.dart

- [ ] **Step 1: 为虚拟网盘条目增加可选展示身份**

保持现有必填字段不变，在 CloudFileEntry 构造函数和类字段中加入：

~~~dart
this.seasonNumber,
this.episodeNumber,
this.variantLabel,
~~~

~~~dart
final int? seasonNumber;
final int? episodeNumber;
final String? variantLabel;
~~~

这些字段全部可空，因此云服务适配器和旧测试夹具无需修改。

- [ ] **Step 2: 集合层生成虚拟条目时保留索引结果**

在 _virtualEntries 的映射中先声明版本标签，并在同集多版本分支中同时写入虚拟文件名和标签：

~~~dart
String? variantLabel;
if (episode != null && (duplicateCounts[episode] ?? 0) > 1) {
  final index = (duplicateIndexes[episode] ?? 0) + 1;
  duplicateIndexes[episode] = index;
  final summary = _releaseSummary(item);
  variantLabel = summary.isEmpty ? '版本 $index' : summary;
  final extension = p.extension(displayName);
  final base = p.basenameWithoutExtension(displayName);
  displayName = '$base [$variantLabel]$extension';
}
~~~

构造虚拟条目时附加：

~~~dart
seasonNumber: item.seasonNumber,
episodeNumber: item.episodeNumber,
variantLabel: variantLabel,
~~~

- [ ] **Step 3: 选集界面优先消费强类型字段**

将 _episodeTile 的解析和标签构造替换为：

~~~dart
final hasIndexedEpisode = video.episodeNumber != null;
final parsed = hasIndexedEpisode
    ? null
    : LocalEpisodeParser().parse(video.remotePath);
final episodeLabel = _episodeLabel(
  seasonNumber: hasIndexedEpisode
      ? video.seasonNumber
      : video.seasonNumber ?? parsed?.seasonNumber,
  episodeNumber: video.episodeNumber ?? parsed?.episodeNumber,
  index: index,
);
final variant = video.variantLabel ?? _variantLabel(video.name);
~~~

把 _episodeLabel 改为只接收强类型值：

~~~dart
static String _episodeLabel({
  required int? seasonNumber,
  required int? episodeNumber,
  required int index,
}) {
  if (episodeNumber == null) return '第 ' + (index + 1).toString() + ' 集';
  final episodeToken = episodeNumber.toString().padLeft(2, '0');
  if (seasonNumber == null) return 'E$episodeToken';
  return 'S' +
      seasonNumber.toString().padLeft(2, '0') +
      'E' +
      episodeToken;
}
~~~

删除不再使用的 LocalEpisodeInfo 导入。保留 LocalEpisodeParser，用于旧条目兼容。

- [ ] **Step 4: 运行聚焦测试并确认转绿**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/cloud_resources_page_test.dart --plain-name "不同资源的重复集号使用索引身份且保留全部版本"
D:/flutter/bin/flutter.bat test --no-pub test/cloud_resource_collection_test.dart test/cloud_resources_page_test.dart
~~~

Expected: PASS；两个 S03E01 版本都使用索引身份，12 行全部保留，旧路径解析测试仍通过。

- [ ] **Step 5: 格式化、检查并提交剧集修复**

~~~powershell
D:/flutter/bin/dart.bat format lib/modules/cloud/cloud_file_entry.dart lib/pages/cloud/resources/cloud_resource_collection.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart test/cloud_resources_page_test.dart
git diff --check
git add -- lib/modules/cloud/cloud_file_entry.dart lib/pages/cloud/resources/cloud_resource_collection.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart test/cloud_resources_page_test.dart
git commit -m "修复网盘多版本重复集号"
~~~

### Task 3: 用失败测试统一本地海报墙布局

**Files:**
- Modify: test/library_presentation_components_test.dart
- Modify: lib/features/library/presentation/library_media_grid.dart

- [ ] **Step 1: 把现有交互测试与布局契约分开**

保留单卡测试中的悬浮、Hero、徽章、点击断言，但删除固定三列/四列委托断言。另建 20 个唯一 ID 的卡片数据：

~~~dart
final layoutItems = <LibraryMediaItemViewData>[
  for (var index = 0; index < 20; index++)
    LibraryMediaItemViewData(
      id: 'show-$index',
      title: '测试动画 $index',
      subtitle: '第 1 季',
      infoText: 'MKV  1.0 GB',
      modifiedText: '2026-07-20',
      hasMultipleEpisodes: true,
      hasSubtitle: false,
      scrapeLabel: '未刮削',
    ),
];
~~~

- [ ] **Step 2: 新增自适应列数测试**

参照网盘海报墙测试，在 620、1320、1920 像素下读取首行卡片数量和宽度：

~~~dart
testWidgets('本地海报墙保持海报尺寸并随宽度增加列数', (tester) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final layoutItems = <LibraryMediaItemViewData>[
    for (var index = 0; index < 20; index++)
      LibraryMediaItemViewData(
        id: 'show-$index',
        title: '测试动画 $index',
        subtitle: '第 1 季',
        infoText: 'MKV  1.0 GB',
        modifiedText: '2026-07-20',
        hasMultipleEpisodes: true,
        hasSubtitle: false,
        scrapeLabel: '未刮削',
      ),
  ];

  Future<void> pumpAt(double width) async {
    tester.view.physicalSize = Size(width, 720);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(items: layoutItems),
          ),
        ),
      ),
    );
  }

  Future<({int columns, double cardWidth})> layoutAt(double width) async {
    await pumpAt(width);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.maxCrossAxisExtent, 300);
    expect(delegate.childAspectRatio, 0.68);
    expect(delegate.crossAxisSpacing, 12);
    expect(delegate.mainAxisSpacing, 12);
    final cards = find.byType(ImmersiveMediaCard);
    final firstTop = tester.getTopLeft(cards.first).dy;
    final firstRow = <Rect>[
      for (var index = 0; index < cards.evaluate().length; index++)
        tester.getRect(cards.at(index)),
    ].where((rect) => (rect.top - firstTop).abs() < 0.5).toList();
    return (
      columns: firstRow.length,
      cardWidth: firstRow.first.width,
    );
  }

  final narrow = await layoutAt(620);
  final regular = await layoutAt(1320);
  final maximized = await layoutAt(1920);

  expect(narrow.columns, lessThan(regular.columns));
  expect(maximized.columns, greaterThan(regular.columns));
  expect(narrow.cardWidth, lessThanOrEqualTo(300));
  expect(regular.cardWidth, lessThanOrEqualTo(300));
  expect(maximized.cardWidth, lessThanOrEqualTo(300));
  expect(tester.takeException(), isNull);
});
~~~

- [ ] **Step 3: 运行测试并确认正确失败**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/library_presentation_components_test.dart --plain-name "本地海报墙保持海报尺寸并随宽度增加列数"
~~~

Expected: FAIL；当前委托是 SliverGridDelegateWithFixedCrossAxisCount，无法满足最大 300 像素和宽屏增列契约。

- [ ] **Step 4: 用最大横轴尺寸委托替换固定断点**

删除 _isDesktop、LayoutBuilder、3/4 列断点和 mainAxisExtent 计算，让已有 GridView.builder 直接使用：

~~~dart
padding: const EdgeInsets.all(12),
gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 300,
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
  childAspectRatio: 0.68,
),
~~~

保留 scrollController、findChildIndexCallback、_LibraryMediaTile、BoxFit.contain 和 ImmersiveMediaCardOverlayMode.hover 原样。

- [ ] **Step 5: 运行组件测试并确认转绿**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/library_presentation_components_test.dart
~~~

Expected: PASS；三个宽度的列数递增且所有卡片不超过 300 像素，原交互测试继续通过。

- [ ] **Step 6: 格式化、检查并提交布局修复**

~~~powershell
D:/flutter/bin/dart.bat format lib/features/library/presentation/library_media_grid.dart test/library_presentation_components_test.dart
git diff --check
git add -- lib/features/library/presentation/library_media_grid.dart test/library_presentation_components_test.dart
git commit -m "统一本地网盘海报墙尺寸"
~~~

### Task 4: 更新 2.1.22 版本契约与普通用户文案

**Files:**
- Modify: pubspec.yaml
- Modify: README.md
- Modify: RELEASE_NOTES.md
- Modify: UPDATE_DIALOG_COPY.md
- Modify: lib/core/app_version.dart
- Modify: lib/utils/version_history.dart
- Modify: test/version_consistency_test.dart
- Modify: test/version_history_current_test.dart
- Modify: test/identity_v2_zero_residue_test.dart

- [ ] **Step 1: 先把版本测试更新为 2.1.22**

在 version_consistency_test.dart 中设置：

~~~dart
const expectedVersion = '2.1.22';
const expectedBuildNumber = '20122';
~~~

在 identity_v2_zero_residue_test.dart 中把当前版本期望改为 2.1.22。在 version_history_current_test.dart 增加：

~~~dart
test('二点一二十二说明重复集号和本地海报尺寸', () {
  final entries = versionHistoryForCurrent('2.1.22');

  expect(entries, hasLength(1));
  final changes = entries.single.changes.join('\n');
  expect(changes, contains('同一集'));
  expect(changes, contains('本地海报墙'));
  expect(changes, contains('海报尺寸'));
  expect(changes, contains('不会修改网盘文件'));
  expect(entries.single.isPrerelease, isTrue);
});
~~~

- [ ] **Step 2: 运行版本测试并确认正确失败**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
~~~

Expected: FAIL；项目仍声明 2.1.21，且版本历史没有 2.1.22。

- [ ] **Step 3: 更新版本号**

pubspec.yaml：

~~~yaml
version: 2.1.22+20122
msix_config:
  msix_version: 2.1.22.0
~~~

AppVersion.current 改为 2.1.22。

- [ ] **Step 4: 更新四处用户文案和 README**

在 RELEASE_NOTES.md 顶部新增 2.1.22，在 versionHistoryList 顶部新增测试版条目，并把 UPDATE_DIALOG_COPY.md 当前版本整体更新为 2.1.22。三处当前版本文案都明确：

- 同一集的不同网盘资源现在使用相同 SxxExx，不再按列表位置误报新集数。
- 所有真实版本仍被保留并显示版本标签，季度卡片按唯一集号计数。
- 本地海报墙最大化时保持海报尺寸上限，只自动增加列数。
- 本次只调整看影音媒体库显示，不会修改网盘文件、目录、远程 ID 或播放路径，应用启动和播放器保持可用。

README 增加本地海报墙自适应说明、补充同集多资源显示规则，并把当前版本改为 2.1.22。

- [ ] **Step 5: 运行版本与发布契约测试**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart test/release_config_contract_test.dart
~~~

Expected: PASS。

- [ ] **Step 6: 检查并提交版本文案**

~~~powershell
git diff --check
git add -- pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布二点一二十二测试版"
~~~

### Task 5: 全量验证、Windows Release 和签名 MSIX 交付

**Files:**
- Verify: entire repository
- Output: build/windows/x64/runner/Release/kanyingyin.exe
- Output: build/windows/x64/runner/Release/kanyingyin.msix
- Deliver: C:/Users/asus/Desktop/看影音-2.1.22.msix

- [ ] **Step 1: 检查代码格式、工作树和差异**

~~~powershell
D:/flutter/bin/dart.bat format lib test
git status --short
git diff --check
git log -8 --oneline
~~~

Expected: 源码和测试格式化完成；没有构建缓存或无关文件进入 Git 变更。

- [ ] **Step 2: 运行全量测试**

Run: D:/flutter/bin/flutter.bat test --no-pub

Expected: 全部测试 PASS，准确记录测试数量和 0 失败。

- [ ] **Step 3: 运行静态分析**

Run: D:/flutter/bin/flutter.bat analyze --no-pub

Expected: No issues found!。

- [ ] **Step 4: 构建 Windows Release 并核对时间**

Run: D:/flutter/bin/flutter.bat build windows --release --no-pub

随后读取 kanyingyin.exe 和 data/app.so 的长度与修改时间，确认均来自本轮构建。

- [ ] **Step 5: 使用现有本机证书生成签名 MSIX**

密码只在当前 PowerShell 进程内解密和清零，不输出或写入明文：

~~~powershell
$secure = Import-Clixml -LiteralPath "$env:USERPROFILE/.kanyingyin/signing/certificate-password.clixml"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  D:/flutter/bin/dart.bat run msix:create --build-windows false --sign-msix true --certificate-path "$env:USERPROFILE/.kanyingyin/signing/certificate.pfx" --certificate-password $plainPassword
} finally {
  $plainPassword = $null
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
~~~

Expected: build/windows/x64/runner/Release/kanyingyin.msix 为本轮新生成的签名包，源码中的 sign_msix: false 保持不变。

- [ ] **Step 6: 验证清单、签名、架构和哈希**

将 MSIX 解包到新建的随机临时目录，读取 AppxManifest.xml，确认：

- Identity Name = com.kanyingyin.player
- Publisher = CN=KanYingYin
- Version = 2.1.22.0
- ProcessorArchitecture = x64
- 包内存在 AppxSignature.p7x
- Get-AuthenticodeSignature 状态为 Valid

复制并复验：

~~~powershell
Copy-Item -LiteralPath 'build/windows/x64/runner/Release/kanyingyin.msix' -Destination 'C:/Users/asus/Desktop/看影音-2.1.22.msix' -Force
Get-AuthenticodeSignature -LiteralPath 'C:/Users/asus/Desktop/看影音-2.1.22.msix'
Get-FileHash -Algorithm SHA256 -LiteralPath 'build/windows/x64/runner/Release/kanyingyin.msix'
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/asus/Desktop/看影音-2.1.22.msix'
~~~

Expected: 源包和桌面包大小、SHA-256 一致，签名均为 Valid。

- [ ] **Step 7: 最终检查交付状态**

~~~powershell
git status --short
git diff --check
git log -10 --oneline
~~~

只提交本轮相关源码、测试和文案。构建目录与 MSIX 不进入 Git；若验证没有产生源码变化，不创建空提交。

## 自检结果

- 规格覆盖：Tasks 1–2 覆盖纯数字真实文件、同集多版本、强类型身份、唯一集数、完整播放行和旧数据回退；Task 3 覆盖本地海报尺寸上限与自适应增列；Task 4 覆盖 2.1.22 版本和用户文案；Task 5 覆盖全量质量门禁、Windows Release、签名、清单、哈希和桌面交付。
- 占位符扫描：计划没有未决占位项或未定义字段；测试夹具、方法签名、版本号、命令和预期结果均已明确。
- 类型一致性：展示字段统一为 seasonNumber、episodeNumber、variantLabel；索引来源统一为 CloudMediaIndexItem；网格委托统一为 SliverGridDelegateWithMaxCrossAxisExtent；版本统一为 2.1.22+20122 / 2.1.22.0。
