# Windows 专属清理、网盘配置入口与 Anime4K 自适应 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在同一测试版中完成 Windows 专属工程收敛、网盘媒体库夸克/百度快速配置入口，以及 Anime4K 按实际放大需求自适应启用和失败恢复。

**Architecture:** 将三组改动保持为可独立验证的纵向切片：网盘页面通过可返回来源 ID 的异步导航回调刷新并优选新来源；Windows 清理由残留守卫测试约束，同时把旧 JSON/Hive 读取隔离在兼容层；Anime4K 由纯判定策略、可注入 mpv 命令执行器和播放器状态编排三层组成。最终统一递增版本，执行完整测试、静态分析、Windows Release、签名 MSIX 和清单验证。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Hive CE、media-kit/mpv、flutter_test、PowerShell、Windows MSIX

---

## 文件结构

### 网盘配置入口

- 修改 `lib/pages/cloud/resources/cloud_resources_page.dart`：增加百度入口、常驻添加菜单、异步添加后刷新与优选新来源。
- 修改 `lib/pages/cloud/resources/cloud_resources_controller.dart`：来源重载支持首选来源 ID，并在重载失败时保留原索引快照。
- 修改 `lib/pages/settings/cloud_sources_settings.dart`：OpenList 继续保留在来源管理，并在说明和添加项中标注“调试中”。
- 修改 `lib/pages/cloud/quark/quark_source_editor.dart`：保存成功后向调用页返回来源 ID。
- 修改 `lib/pages/cloud/baidu/baidu_source_editor.dart`：保存成功后向调用页返回来源 ID。
- 修改 `test/cloud_resources_page_test.dart`：覆盖空状态、常驻菜单、新来源优选和失败保留。
- 修改 `test/cloud_sources_ui_test.dart`：覆盖来源管理仍提供 OpenList 且明确标注调试状态。

### Windows 专属清理与兼容层

- 修改 `lib/app_widget.dart`、`lib/pages/init_page.dart`、`lib/providers/theme_provider.dart`、`lib/pages/settings/theme_settings_page.dart`：删除动态配色和 Android 显示模式。
- 修改 `lib/pages/settings/player_settings.dart`、`lib/pages/settings/settings_module.dart`：删除 Android 渲染器、OpenSLES 和自动画中画设置。
- 删除 `lib/pages/settings/renderer_settings.dart`、`lib/pages/settings/displaymode_settings.dart`。
- 修改 `lib/main.dart`、`lib/utils/window_utils.dart`、`lib/utils/display_utils.dart`、`lib/utils/utils.dart`、`lib/utils/pip_utils.dart`：只保留 Windows 启动、显示、全屏和桌面画中画实现。
- 修改 `lib/pages/player/player_controller.dart`、`lib/pages/player/player_item.dart`、`lib/pages/player/player_item_panel.dart`、`lib/pages/player/smallest_player_item_panel.dart`、`lib/pages/video/video_page.dart`：删除移动端音量、亮度、截图、渲染器、画中画和外部播放器分支，保留 Windows 行为。
- 修改 `lib/services/audio_controller.dart`：删除 Linux MPRIS 和移动端音频中断分支，保留 Windows `audio_service_win`；保留 `audio_session`，直到 Windows 回归验证证明播放器不需要它。
- 修改 `lib/utils/proxy_manager.dart`、`lib/utils/constants.dart`、`lib/utils/storage.dart`：删除旧平台、旧在线项目注释、请求头和不再使用的设置键。
- 修改 `pubspec.yaml`、`pubspec.lock`：移除无 Windows 调用路径的依赖与非 Windows overrides，保留 `flutter_volume_controller` 和 `audio_session`。
- 删除 `assets/linux/`、`assets/images/logo/logo_android.png`、`assets/images/logo/logo_ios.png`、`assets/images/logo/logo_linux.png`。
- 重新生成 `windows/flutter/generated_plugin_registrant.cc`、`windows/flutter/generated_plugins.cmake`。
- 修改 `test/settings_ui_residue_test.dart`，新增 `test/windows_only_residue_test.dart`：把 Windows 边界变成自动化守卫。

### 旧数据兼容和活动命名

- 新建 `lib/legacy/local_index/legacy_local_media_index_parser.dart`：唯一允许读取旧 `bangumi*` JSON 键的隔离解析器。
- 新建 `lib/modules/video/playback_media_item.dart`：活动播放器使用的中性媒体条目。
- 新建 `lib/legacy/hive/legacy_playback_media_item_adapter.dart`：保留已发布 Hive `typeId: 0` 的读取能力，并写入中性字段。
- 新建 `lib/legacy/hive/legacy_bangumi_tag.dart`、`lib/legacy/hive/legacy_bangumi_tag_adapter.dart`：仅为旧 Hive 字段 9 的反序列化保留 `typeId: 4`。
- 删除 `lib/modules/bangumi/bangumi_item.dart`、`lib/modules/bangumi/bangumi_item.g.dart`、`lib/modules/bangumi/bangumi_tag.dart`、`lib/modules/bangumi/bangumi_tag.g.dart` 和旧 API JSON 测试。
- 修改 `lib/modules/local/local_media_index_item.dart`、`lib/services/local_media_index_metadata_refresher.dart`：活动索引不再携带或写回旧字段。
- 修改 `lib/modules/video/local_playback_request.dart`、`lib/services/local_playback_request_builder.dart`、`lib/pages/video/video_page_controller_interface.dart`、`lib/pages/video/local_video_controller.dart`、`lib/pages/player/player_controller.dart`、`lib/pages/player/player_item.dart`：将活动 `BangumiItem`/`bangumiId`/`bangumiName` 改为媒体语义。
- 修改 `lib/pages/local/local_controller.dart`、`lib/pages/local/local_controller.g.dart`、`lib/pages/local/local_page.dart`：将批量匹配状态改为 TMDB 语义并重新生成 MobX 文件。
- 修改 `test/local_media_index_tmdb_test.dart`，新增 `test/legacy_playback_media_item_adapter_test.dart`：验证旧 JSON/Hive 可读、新数据不再写旧键。

### Anime4K 自适应

- 新建 `lib/features/player/application/anime4k_policy.dart`：无 Flutter 控件和 mpv 依赖的判定模型。
- 新建 `lib/features/player/application/anime4k_coordinator.dart`：负责决策去重、失败锁定和可测试执行编排。
- 新建 `lib/features/player/application/anime4k_shader_executor.dart`：封装 `glsl-shaders` 设置与失败清空。
- 新建 `lib/pages/player/widgets/anime4k_status_label.dart`：统一播放器菜单中的选择档位和实际运行状态文案。
- 修改 `lib/pages/player/player_controller.dart`、`lib/pages/player/player_controller.g.dart`：维护用户档位、运行状态、250ms 防抖、去重和失败锁定。
- 修改 `lib/pages/player/player_item_surface.dart`：把播放区域物理像素尺寸传给控制器。
- 修改 `lib/pages/player/player_item.dart`、`lib/pages/player/player_item_panel.dart`、`lib/pages/player/smallest_player_item_panel.dart`：所有切换 `await`，显示实际状态并只提示一次失败。
- 修改 `lib/pages/settings/super_resolution_settings.dart`：Windows 文案和默认档位使用强类型映射。
- 新增 `test/anime4k_policy_test.dart`、`test/anime4k_shader_executor_test.dart`、`test/anime4k_player_ui_test.dart`。

### 版本与交付

- 修改 `pubspec.yaml`、`lib/core/app_version.dart`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`README.md`、`lib/utils/version_history.dart`：发布 `2.1.48+20148` / `2.1.48.0` 测试版。
- 使用 `tool/windows/build_signed_release.ps1` 生成并验证签名包，桌面文件为 `看影音-2.1.48.msix`。

### Task 1: 网盘空状态和常驻添加菜单

**Files:**
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `test/cloud_sources_ui_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `lib/pages/settings/cloud_sources_settings.dart`

- [ ] **Step 1: 写空状态和已有来源菜单的失败测试**

将原“无来源时显示两种添加入口”测试改为以下断言，并新增常驻菜单测试：

```dart
testWidgets('无来源时只显示夸克和百度添加入口', (tester) async {
  final fixture = await _PageFixture.create();
  var quarkCalls = 0;
  var baiduCalls = 0;

  await tester.pumpWidget(MaterialApp(
    home: CloudResourcesPage(
      controller: fixture.controller,
      onAddQuark: () async {
        quarkCalls++;
        return null;
      },
      onAddBaidu: () async {
        baiduCalls++;
        return null;
      },
    ),
  ));
  await tester.pumpAndSettle();

  expect(find.text('添加夸克网盘'), findsOneWidget);
  expect(find.text('添加百度网盘'), findsOneWidget);
  expect(find.text('添加 OpenList'), findsNothing);
  await tester.tap(find.text('添加夸克网盘'));
  await tester.pump();
  await tester.tap(find.text('添加百度网盘'));
  await tester.pump();
  expect((quarkCalls, baiduCalls), (1, 1));
  fixture.controller.dispose();
});

testWidgets('已有来源时常驻添加网盘菜单只提供夸克和百度', (tester) async {
  final fixture = await _PageFixture.create(source: _quarkSource);
  await tester.pumpWidget(MaterialApp(
    home: CloudResourcesPage(controller: fixture.controller),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('添加网盘'));
  await tester.pumpAndSettle();
  expect(find.text('添加夸克网盘'), findsOneWidget);
  expect(find.text('添加百度网盘'), findsOneWidget);
  expect(find.textContaining('OpenList'), findsNothing);
  fixture.controller.dispose();
});

testWidgets('来源管理保留 OpenList 并标注调试中', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: CloudSourcesSettingsPage()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('添加网盘来源'));
  await tester.pumpAndSettle();
  expect(find.text('添加 OpenList（调试中）'), findsOneWidget);
});
```

前两个测试写入 `cloud_resources_page_test.dart`；第三个测试写入 `cloud_sources_ui_test.dart`，并把该文件原有“添加菜单包含 OpenList”断言同步改为带“（调试中）”的完整文案。

- [ ] **Step 2: 运行测试并确认因百度回调和菜单不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，提示 `onAddBaidu` 未定义或找不到“添加百度网盘”/“添加网盘”。

- [ ] **Step 3: 增加异步添加回调和两个 UI 入口**

在 `cloud_resources_page.dart` 定义回调类型并替换构造参数：

```dart
typedef CloudSourceAddCallback = FutureOr<String?> Function();

class CloudResourcesPage extends StatefulWidget {
  const CloudResourcesPage({
    super.key,
    this.controller,
    this.onAddQuark,
    this.onAddBaidu,
    this.onManageSources,
    this.onPlayRequest,
    this.onDeleteSource,
  });

  final CloudResourcesController? controller;
  final CloudSourceAddCallback? onAddQuark;
  final CloudSourceAddCallback? onAddBaidu;
  final VoidCallback? onManageSources;
  final FutureOr<void> Function(CloudResourcePlaybackRequest request)? onPlayRequest;
  final FutureOr<void> Function(String sourceId)? onDeleteSource;
}
```

加入统一添加方法和工具栏菜单枚举：

```dart
enum _CloudAddAction { quark, baidu }

Future<void> _addCloudSource(_CloudAddAction action) async {
  final callback = action == _CloudAddAction.quark
      ? widget.onAddQuark
      : widget.onAddBaidu;
  final route = action == _CloudAddAction.quark
      ? '/settings/cloud-sources/quark/edit'
      : '/settings/cloud-sources/baidu/edit';
  final sourceId = callback != null
      ? await callback()
      : await Modular.to.pushNamed<String>(route);
  if (!mounted || sourceId == null) return;
  await _controller.reloadSourcesAndSnapshot(preferredSourceId: sourceId);
}
```

在管理按钮前加入：

```dart
PopupMenuButton<_CloudAddAction>(
  tooltip: '添加网盘',
  icon: const Icon(Icons.add_circle_outline),
  onSelected: _addCloudSource,
  itemBuilder: (_) => const [
    PopupMenuItem(
      value: _CloudAddAction.quark,
      child: Text('添加夸克网盘'),
    ),
    PopupMenuItem(
      value: _CloudAddAction.baidu,
      child: Text('添加百度网盘'),
    ),
  ],
),
```

空状态按钮改为 `_addCloudSource(_CloudAddAction.quark)` 和 `_addCloudSource(_CloudAddAction.baidu)`，删除 `_addOpenList()` 及 `onAddOpenList`。

来源管理页把说明改为“管理个人夸克、百度与 OpenList 网盘媒体来源；OpenList 功能仍在调试”，并把空状态和添加菜单中的 OpenList 文案统一改为 `添加 OpenList（调试中）`；路由和编辑器继续保留。

- [ ] **Step 4: 运行页面测试并确认入口测试通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_sources_ui_test.dart`

Expected: 新增两个测试 PASS；如因控制器尚无 `preferredSourceId` 参数而编译失败，进入 Task 2，不临时弱化断言。

- [ ] **Step 5: 提交网盘入口 UI**

```powershell
git add lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/settings/cloud_sources_settings.dart test/cloud_resources_page_test.dart test/cloud_sources_ui_test.dart
git commit -m "功能：增加夸克和百度网盘快捷入口"
```

### Task 2: 添加完成后优选新来源并保护旧快照

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/cloud/quark/quark_source_editor.dart`
- Modify: `lib/pages/cloud/baidu/baidu_source_editor.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写来源优选和失败保留测试**

在控制器测试夹具使用的内存仓库中加入可变来源列表和 `failGetAll` 开关，再增加：

```dart
test('重载后优先选择刚创建的来源', () async {
  final storage = _SwitchableCloudSourceStorage();
  final repository = CloudSourceRepository(
    storage: storage,
    credentialStore: MemoryCloudCredentialStore(),
  );
  await repository.save(_quarkSource);
  final fixture = await _PageFixture.create(repository: repository);
  await fixture.controller.load();
  const baidu = CloudSource(
    id: 'baidu-new',
    type: CloudSourceType.baidu,
    name: '百度网盘',
    baseUrl: 'https://pan.baidu.com',
    rootPaths: <String>['/视频'],
    rootRefs: <CloudRemoteRef>[CloudRemoteRef(id: 'root', path: '/视频')],
  );
  await repository.save(baidu);

  await fixture.controller.reloadSourcesAndSnapshot(
    preferredSourceId: baidu.id,
  );

  expect(fixture.controller.selectedSource?.id, baidu.id);
  fixture.controller.dispose();
});

test('重载来源失败时保留当前来源和已有媒体索引', () async {
  final storage = _SwitchableCloudSourceStorage();
  final repository = CloudSourceRepository(
    storage: storage,
    credentialStore: MemoryCloudCredentialStore(),
  );
  await repository.save(_quarkSource);
  final fixture = await _PageFixture.create(
    repository: repository,
    source: _quarkSource,
    entries: const <CloudFileEntry>[
      CloudFileEntry(
        id: 'video',
        remotePath: '/影视/a.mkv',
        name: 'a.mkv',
        size: 700 * 1024 * 1024,
        modifiedAt: null,
        isDirectory: false,
      ),
    ],
  );
  await fixture.controller.load();
  storage.failReads = true;

  await fixture.controller.reloadSourcesAndSnapshot(
    preferredSourceId: 'missing',
  );

  expect(fixture.controller.selectedSource?.id, _quarkSource.id);
  expect(fixture.controller.entries.single.id, 'video');
  expect(fixture.controller.errorMessage, '网盘来源加载失败，请重试');
  fixture.controller.dispose();
});

class _SwitchableCloudSourceStorage extends MemoryCloudSourceStorage {
  bool failReads = false;

  @override
  Future<List<Map<String, dynamic>>> read() {
    if (failReads) throw StateError('read failed');
    return super.read();
  }
}
```

同时给 `_PageFixture.create` 增加可选 `CloudSourceRepository? repository` 参数，并将内部局部变量改为：

```dart
final sourceRepository = repository ?? CloudSourceRepository(
  storage: MemoryCloudSourceStorage(),
  credentialStore: credentials,
);
if (source != null) await sourceRepository.save(source);
```

构造 `CloudResourcesController` 时传 `repository: sourceRepository`，保证测试和控制器共用同一仓库。

- [ ] **Step 2: 运行测试并确认当前重载清空状态或无法优选来源**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，首选来源未生效，或失败后 `selectedSource`/`entries` 被清空。

- [ ] **Step 3: 让来源重载支持首选 ID 和事务式失败恢复**

将控制器入口改为：

```dart
Future<void> reloadSourcesAndSnapshot({String? preferredSourceId}) async {
  _scanToken?.cancel();
  await scanCompletion;
  await _loadSources(
    startScan: false,
    preferredSourceId: preferredSourceId,
    preserveSnapshotOnFailure: true,
  );
}
```

扩展 `_loadSources`，进入加载前保存 `sources`、`selectedSource`、`entries`、`_indexedItems`、`_works`、`_mediaTree`，成功时按以下顺序选 ID：

```dart
final currentId = selectedSource?.id;
final nextId = loadedSources.any((source) => source.id == preferredSourceId)
    ? preferredSourceId
    : loadedSources.any((source) => source.id == currentId)
        ? currentId
        : loadedSources.firstOrNull?.id;
```

捕获异常且 `preserveSnapshotOnFailure` 为真时恢复保存的集合和选中来源，设置：

```dart
loading = false;
scanning = false;
errorMessage = '网盘来源加载失败，请重试';
_notify();
```

首次 `load()` 继续使用 `preserveSnapshotOnFailure: false`，以保持原有空状态语义。

- [ ] **Step 4: 编辑页保存成功时返回来源 ID**

将夸克和百度编辑页末尾的无值返回：

```dart
if (mounted) Navigator.of(context).maybePop();
```

替换为：

```dart
if (mounted) Navigator.of(context).pop(source.id);
```

目录保存成功但媒体库刷新失败时仍停留在编辑页并提示，不返回 ID。

- [ ] **Step 5: 运行网盘页面和编辑页定向测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\quark_source_editor_test.dart test\baidu_source_editor_test.dart`

Expected: PASS；添加后选中新来源，重载失败保留原海报索引。

- [ ] **Step 6: 提交来源刷新闭环**

```powershell
git add lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/quark/quark_source_editor.dart lib/pages/cloud/baidu/baidu_source_editor.dart test/cloud_resources_page_test.dart test/quark_source_editor_test.dart test/baidu_source_editor_test.dart
git commit -m "修复：添加网盘后刷新并选中新来源"
```

### Task 3: 清理 Windows 设置页和主题残留

**Files:**
- Modify: `test/settings_ui_residue_test.dart`
- Modify: `lib/app_widget.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `lib/providers/theme_provider.dart`
- Modify: `lib/pages/settings/theme_settings_page.dart`
- Modify: `lib/pages/settings/player_settings.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Delete: `lib/pages/settings/displaymode_settings.dart`
- Delete: `lib/pages/settings/renderer_settings.dart`
- Modify: `lib/utils/storage.dart`

- [ ] **Step 1: 写 Windows 设置残留失败测试**

在 `settings_ui_residue_test.dart` 删除已移除页面的表现层断言，并加入：

```dart
test('Windows 设置不暴露动态配色和移动端播放选项', () {
  final paths = <String>[
    'lib/app_widget.dart',
    'lib/pages/init_page.dart',
    'lib/providers/theme_provider.dart',
    'lib/pages/settings/theme_settings_page.dart',
    'lib/pages/settings/player_settings.dart',
    'lib/pages/settings/settings_module.dart',
    'lib/utils/storage.dart',
  ];
  const forbidden = <String>[
    'DynamicColorBuilder',
    'useDynamicColor',
    'setDynamic(',
    'androidEnableOpenSLES',
    'androidAutoEnterPIP',
    'androidVideoRenderer',
    '/player/renderer',
    '/theme/display',
    'OpenSLES',
    '自动进入画中画',
  ];
  for (final path in paths) {
    final source = File(path).readAsStringSync();
    for (final token in forbidden) {
      expect(source, isNot(contains(token)), reason: '$path: $token');
    }
  }
  expect(File('lib/pages/settings/displaymode_settings.dart').existsSync(), isFalse);
  expect(File('lib/pages/settings/renderer_settings.dart').existsSync(), isFalse);
});
```

- [ ] **Step 2: 运行测试并确认残留被检出**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\settings_ui_residue_test.dart`

Expected: FAIL，列出动态配色、Android 播放设置和两个移动端页面。

- [ ] **Step 3: 将应用主题改为固定手动配色**

从 `ThemeProvider` 删除 `useDynamicColor` 与 `setDynamic`；从 `InitPage` 删除动态配色延迟初始化；从 `ThemeSettingsPage` 删除动态配色开关，并让“配色方案”始终可用。

将 `app_widget.dart` 的 `DynamicColorBuilder` 外层替换为直接构建：

```dart
final lightTheme = themeProvider.light.copyWith(
  textTheme: themeProvider.light.textTheme.apply(
    fontFamily: themeProvider.currentFontFamily,
  ),
);
final darkTheme = themeProvider.dark.copyWith(
  textTheme: themeProvider.dark.textTheme.apply(
    fontFamily: themeProvider.currentFontFamily,
  ),
);
return MaterialApp.router(
  title: AppIdentity.displayName,
  theme: lightTheme,
  darkTheme: darkTheme,
  themeMode: themeProvider.themeMode,
  routerConfig: Modular.routerConfig,
);
```

保留现有 `builder`、本地化、快捷键、滚动行为和窗口壳参数；这里只移除 `DynamicColorBuilder` 及动态 scheme 分支。

- [ ] **Step 4: 删除 Android 设置状态、路由和存储键**

从 `PlayerSettingsPage` 删除 `androidEnableOpenSLES`、`androidAutoEnterPIP` 的字段、读取和 tile；从 `SettingsModule` 删除两个 import 和路由；从 `SettingBoxKey` 删除：

```dart
useDynamicColor,
displayMode,
androidEnableOpenSLES,
androidVideoRenderer,
androidAutoEnterPIP,
```

删除 `displaymode_settings.dart` 和 `renderer_settings.dart`。保留 Windows 硬件解码、低内存、后台播放、字幕、动画、Anime4K 和画中画按钮。

- [ ] **Step 5: 运行设置测试和静态分析**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\settings_ui_residue_test.dart test\local_only_settings_test.dart`

Expected: PASS。

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: 若只剩后续平台清理相关错误，记录具体文件；不得用 ignore 压制。

- [ ] **Step 6: 提交设置收敛**

```powershell
git add lib/app_widget.dart lib/pages/init_page.dart lib/providers/theme_provider.dart lib/pages/settings/theme_settings_page.dart lib/pages/settings/player_settings.dart lib/pages/settings/settings_module.dart lib/utils/storage.dart test/settings_ui_residue_test.dart
git add -u lib/pages/settings/displaymode_settings.dart lib/pages/settings/renderer_settings.dart
git commit -m "重构：收敛 Windows 主题和播放设置"
```

### Task 4: 清理非 Windows 运行分支、依赖和资产

**Files:**
- Create: `test/windows_only_residue_test.dart`
- Modify: `lib/main.dart`
- Modify: `lib/app_widget.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `lib/utils/window_utils.dart`
- Modify: `lib/utils/display_utils.dart`
- Modify: `lib/utils/utils.dart`
- Modify: `lib/utils/pip_utils.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/smallest_player_item_panel.dart`
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/services/audio_controller.dart`
- Modify: `lib/services/windows_app_shell_service.dart`
- Modify: `lib/bean/widget/embedded_native_control_area.dart`
- Modify: `lib/bean/appbar/sys_app_bar.dart`
- Modify: `lib/utils/proxy_manager.dart`
- Modify: `lib/pages/local/local_directory_picker.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Delete: `assets/linux/com.kanyingyin.player.desktop`
- Delete: `assets/linux/DEBIAN/postinst`
- Delete: `assets/linux/DEBIAN/postrm`
- Delete: `assets/images/logo/logo_android.png`
- Delete: `assets/images/logo/logo_ios.png`
- Delete: `assets/images/logo/logo_linux.png`
- Modify (generated): `windows/flutter/generated_plugin_registrant.cc`
- Modify (generated): `windows/flutter/generated_plugins.cmake`

- [ ] **Step 1: 写 Windows 运行边界和依赖失败测试**

新建 `test/windows_only_residue_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('活动源码不再包含非 Windows 平台分支', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.startsWith('lib/legacy/')) continue;
      final source = entity.readAsStringSync();
      for (final token in const <String>[
        'Platform.isAndroid',
        'Platform.isIOS',
        'Platform.isLinux',
        'Platform.isMacOS',
        'kIsWeb',
        'SystemChrome.',
        'DeviceOrientation.',
        'SaverGallery',
        'ScreenBrightnessPlatform',
      ]) {
        if (source.contains(token)) offenders.add('$normalized: $token');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('pubspec 只声明 Windows 所需插件和覆盖', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final token in const <String>[
      'cupertino_icons:',
      'audio_service_mpris:',
      'dynamic_color:',
      'flutter_displaymode:',
      'saver_gallery:',
      'screen_brightness_android:',
      'screen_brightness_ios:',
      'screen_brightness_ohos:',
      'screen_brightness_platform_interface:',
      'media_kit_libs_linux:',
      'media_kit_libs_ios_video:',
      'media_kit_libs_android_video:',
      'media_kit_libs_macos_video:',
      'media_kit_libs_ohos:',
      'flutter_native_splash:',
    ]) {
      expect(pubspec, isNot(contains(token)), reason: token);
    }
    expect(pubspec, contains('flutter_volume_controller:'));
    expect(pubspec, contains('audio_session:'));
    expect(pubspec, contains('media_kit_libs_windows_video:'));
  });

  test('非 Windows 资产已移除', () {
    for (final path in const <String>[
      'assets/linux',
      'assets/images/logo/logo_android.png',
      'assets/images/logo/logo_ios.png',
      'assets/images/logo/logo_linux.png',
    ]) {
      expect(FileSystemEntity.typeSync(path), FileSystemEntityType.notFound,
          reason: path);
    }
  });
}
```

- [ ] **Step 2: 运行守卫测试并确认列出当前平台残留**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\windows_only_residue_test.dart`

Expected: FAIL，列出非 Windows 分支、依赖和资产。

- [ ] **Step 3: 收敛 Windows 工具和播放器分支**

按以下确定映射实施，不改变播放器控件层级或动画参数：

```dart
// WindowUtils
static Future<void> enterFullScreen({bool lockOrientation = true}) =>
    windowManager.setFullScreen(true);
static Future<void> exitFullScreen({bool lockOrientation = true}) =>
    windowManager.setFullScreen(false);

// DisplayUtils
static bool isDesktop() => true;
static bool isCompact() => false;
static bool isTablet() => false;

// PipUtils 只保留
static Size getPIPAspectSize(...);
static Future<void> enterDesktopPIPWindow(...);
static Future<void> exitDesktopPIPWindow();
```

播放器具体收敛：

- `PlayerController` 初始化始终使用 mpv 音量，不再读取系统移动端音量；删除 OpenSLES、Android renderer 和 mobile 外部播放器分支。
- `PlayerItem` 截图在 Windows 使用 `file_picker` 选择保存位置并通过 `File(path).writeAsBytes(screenshot)` 写入；删除图库、亮度和 Android PIP 生命周期。
- 两个播放器 panel 的画中画按钮只调用桌面 `PipUtils`，保留原图标、tooltip、菜单位置和点击节奏。
- `VideoPage` 删除移动端亮度 reset。
- `AudioController` 删除 MPRIS 初始化与 `becomingNoisyEventStream` 分支，保留 `AudioSession.instance/configure/setActive` 和 `audio_service_win`。
- `WindowUtils`、`DisplayUtils`、`WindowsAppShellService`、原生标题栏组件和目录选择器去掉 Linux/macOS/iOS fallback，只保留 Windows 路径。
- `ProxyManager._detectLocalProxy` 直接执行 Windows 本机端口探测，注释只写 TMDB/在线元数据，不出现 WebView 或 Bangumi。

Windows 截图核心实现为：

```dart
final target = await FilePicker.platform.saveFile(
  dialogTitle: '保存截图',
  fileName: '看影音-${DateTime.now().millisecondsSinceEpoch}.png',
  type: FileType.custom,
  allowedExtensions: const <String>['png'],
);
if (target == null) return;
await File(target).writeAsBytes(screenshot, flush: true);
AppDialog.showToast(message: '截图已保存');
```

- [ ] **Step 4: 清理依赖、配置和资产后重新解析依赖**

从 `pubspec.yaml` 删除守卫测试列出的依赖、非 Windows overrides 和 `flutter_native_splash` 配置；`flutter_launcher_icons` 只保留：

```yaml
flutter_launcher_icons:
  windows:
    generate: true
    image_path: assets/images/logo/logo_rounded.png
    icon_size: 256
```

保留 `flutter_volume_controller`，因为播放器快捷音量控件仍调用其 Windows 插件；保留 `audio_session`，因为播放会话仍配置和激活它。删除列出的资产，然后运行：

Run: `D:\flutter\bin\flutter.bat pub get`

Expected: exit 0，并自动移除 Windows 注册文件中的 `dynamic_color`；`generated_plugin_registrant.cc` 和 `generated_plugins.cmake` 只由 Flutter 生成，不手改。

- [ ] **Step 5: 运行 Windows 守卫、相关播放器测试和分析**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\windows_only_residue_test.dart test\player_exit_lifecycle_test.dart test\external_player_test.dart test\player_subtitle_render_strategy_test.dart`

Expected: PASS。

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: 无错误；任何未使用 import 直接移除。

- [ ] **Step 6: 提交 Windows 运行时和依赖清理**

```powershell
git add lib/main.dart lib/app_widget.dart lib/pages/init_page.dart lib/utils/window_utils.dart lib/utils/display_utils.dart lib/utils/utils.dart lib/utils/pip_utils.dart lib/pages/player/player_controller.dart lib/pages/player/player_item.dart lib/pages/player/player_item_panel.dart lib/pages/player/smallest_player_item_panel.dart lib/pages/video/video_page.dart lib/services/audio_controller.dart lib/services/windows_app_shell_service.dart lib/bean/widget/embedded_native_control_area.dart lib/bean/appbar/sys_app_bar.dart lib/utils/proxy_manager.dart lib/pages/local/local_directory_picker.dart pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake test/windows_only_residue_test.dart
git add -u assets/linux assets/images/logo/logo_android.png assets/images/logo/logo_ios.png assets/images/logo/logo_linux.png
git commit -m "重构：清理非 Windows 运行时和依赖"
```

### Task 5: 隔离旧本地索引 JSON 兼容

**Files:**
- Create: `lib/legacy/local_index/legacy_local_media_index_parser.dart`
- Modify: `lib/modules/local/local_media_index_item.dart`
- Modify: `lib/services/local_media_index_metadata_refresher.dart`
- Modify: `test/local_media_index_tmdb_test.dart`

- [ ] **Step 1: 写新索引不回写旧键和坏元数据不丢视频的失败测试**

在 `local_media_index_tmdb_test.dart` 加入：

```dart
test('迁移旧字段后新 JSON 不再写回旧键', () {
  final restored = LocalMediaIndexItem.fromJson(_legacyIndexJson());
  final encoded = restored.toJson();

  expect(restored.tmdb?.id, 456);
  for (final key in const <String>[
    'bangumiId',
    'bangumiName',
    'bangumiNameCn',
    'bangumiRatingScore',
    'bangumiAirDate',
    'bangumiSummary',
    'bangumiCoverUrl',
  ]) {
    expect(encoded, isNot(contains(key)), reason: key);
  }
});

test('旧元数据损坏时仍保留视频索引', () {
  final json = _legacyIndexJson()..['bangumiId'] = <String>['bad'];
  final restored = LocalMediaIndexItem.fromJson(json);

  expect(restored.path, r'D:\Video\Movie.mkv');
  expect(restored.name, 'Movie.mkv');
  expect(restored.tmdb, isNull);
});

Map<String, dynamic> _legacyIndexJson() => <String, dynamic>{
      'path': r'D:\Video\Movie.mkv',
      'name': 'Movie.mkv',
      'parentPath': r'D:\Video',
      'sourcePath': r'D:\Video',
      'size': 100,
      'modifiedMillis': DateTime(2026).millisecondsSinceEpoch,
      'seriesName': 'Movie',
      'indexedAtMillis': DateTime(2026).millisecondsSinceEpoch,
      'bangumiId': 456,
      'bangumiName': 'Movie',
      'bangumiNameCn': '旧中文名',
      'bangumiSummary': '旧简介',
      'bangumiCoverUrl': 'https://example.com/cover.jpg',
    };
```

辅助函数返回现有旧索引夹具，不加入网络请求。

- [ ] **Step 2: 运行测试并确认当前 `toJson` 仍写旧键**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_media_index_tmdb_test.dart`

Expected: FAIL，新 JSON 包含 `bangumi*` 键，坏值路径未经过隔离解析器。

- [ ] **Step 3: 实现只读兼容解析器**

新建 `legacy_local_media_index_parser.dart`：

```dart
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

abstract final class LegacyLocalMediaIndexParser {
  static TmdbMetadata? parseTmdb(Map<String, dynamic> json) {
    try {
      final id = _int(json['bangumiId']);
      if (id == null || id <= 0) return null;
      return TmdbMetadata(
        id: id,
        mediaType: TmdbMediaType.tv,
        title: _text(json['bangumiNameCn']) ??
            _text(json['bangumiName']) ??
            '',
        originalTitle: _text(json['bangumiName']),
        overview: _text(json['bangumiSummary']),
        releaseDate: _text(json['bangumiAirDate']),
        rating: _double(json['bangumiRatingScore']),
        posterUrl: _text(json['bangumiCoverUrl']),
        language: 'zh-CN',
        matchedAt: _date(json['indexedAtMillis']),
        matchConfidence: 0,
      );
    } on Object {
      return null;
    }
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;
  static double? _double(Object? value) => value is num ? value.toDouble() : null;
  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static DateTime _date(Object? value) {
    final millis = _int(value) ?? 0;
    return millis <= 0
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
```

- [ ] **Step 4: 从活动索引模型移除旧字段**

从 `LocalMediaIndexItem` 的字段、构造函数、`fromJson`、`toJson`、`copyWith` 全部删除七个 `bangumi*` 成员。`_parseTmdb` 只做：

```dart
static TmdbMetadata? _parseTmdb(Map<String, dynamic> json) {
  final rawTmdb = json['tmdb'];
  if (rawTmdb is Map) {
    try {
      return TmdbMetadata.fromJson(Map<String, dynamic>.from(rawTmdb));
    } on Object {
      return null;
    }
  }
  return LegacyLocalMediaIndexParser.parseTmdb(json);
}
```

`LocalMediaIndexMetadataRefresher` 构造新对象时不再复制旧字段，只复制 `tmdb` 和当前锁定/识别字段。

- [ ] **Step 5: 运行索引、仓库和扫描回归测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_media_index_tmdb_test.dart test\local_media_index_metadata_refresher_test.dart test\local_media_indexer_test.dart test\local_media_scanner_test.dart`

Expected: PASS；旧字段仅在兼容解析器和兼容测试夹具中出现。

- [ ] **Step 6: 提交 JSON 兼容隔离**

```powershell
git add lib/legacy/local_index/legacy_local_media_index_parser.dart lib/modules/local/local_media_index_item.dart lib/services/local_media_index_metadata_refresher.dart test/local_media_index_tmdb_test.dart
git commit -m "重构：隔离旧媒体索引兼容读取"
```

### Task 6: 用中性播放媒体模型保留 Hive typeId

**Files:**
- Create: `lib/modules/video/playback_media_item.dart`
- Create: `lib/legacy/hive/legacy_playback_media_item_adapter.dart`
- Create: `lib/legacy/hive/legacy_bangumi_tag.dart`
- Create: `lib/legacy/hive/legacy_bangumi_tag_adapter.dart`
- Create: `test/legacy_playback_media_item_adapter_test.dart`
- Modify: `lib/utils/storage.dart`
- Modify: `lib/modules/video/local_playback_request.dart`
- Modify: `lib/services/local_playback_request_builder.dart`
- Modify: `lib/pages/video/video_page_controller_interface.dart`
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_item.dart`
- Delete: `lib/modules/bangumi/bangumi_item.dart`
- Delete: `lib/modules/bangumi/bangumi_item.g.dart`
- Delete: `lib/modules/bangumi/bangumi_tag.dart`
- Delete: `lib/modules/bangumi/bangumi_tag.g.dart`
- Delete: `test/bangumi_item_from_json_test.dart`

- [ ] **Step 1: 写旧 Hive 字段编号读取和新值往返失败测试**

新建测试，使用临时 Hive 目录并验证固定 typeId：

```dart
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('kanyingyin-hive-');
    Hive.init(temp.path);
    Hive.registerAdapter(LegacyBangumiTagAdapter());
    Hive.registerAdapter(LegacyPlaybackMediaItemAdapter());
  });

  tearDown(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('兼容适配器继续占用已发布 typeId', () {
    expect(LegacyPlaybackMediaItemAdapter().typeId, 0);
    expect(LegacyBangumiTagAdapter().typeId, 4);
  });

  test('中性播放条目可以通过旧 typeId 往返', () async {
    final box = await Hive.openBox<Object?>('legacy-media');
    const item = PlaybackMediaItem(
      id: 42,
      title: '原始标题',
      displayTitle: '中文标题',
      summary: '简介',
      artworkUrl: 'poster.jpg',
    );
    await box.put('item', item);
    expect(await box.get('item'), item);
  });
}
```

- [ ] **Step 2: 运行测试并确认新模型和适配器尚不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\legacy_playback_media_item_adapter_test.dart`

Expected: FAIL，找不到 `PlaybackMediaItem` 和兼容适配器。

- [ ] **Step 3: 确认旧 Hive 类型没有仍在写入的业务仓库**

Run: `rg -n "BangumiItem|BangumiTag|Hive\.openBox|\.put\(" lib -g "*.dart"`

Expected: 旧类型只出现在当前待删除模型和 `GStorage` 适配器注册中，没有专门保存 `BangumiItem` 的活动仓库；因此本阶段保留二进制适配器即可，不新增虚构的数据重写仓库。若命令发现真实写入调用，先把该调用改为读取后用原仓库原子写入 `PlaybackMediaItem`，再继续下一步。

- [ ] **Step 4: 实现中性模型和手写兼容适配器**

`playback_media_item.dart`：

```dart
class PlaybackMediaItem {
  const PlaybackMediaItem({
    required this.id,
    required this.title,
    required this.displayTitle,
    this.summary = '',
    this.artworkUrl,
  });

  final int id;
  final String title;
  final String displayTitle;
  final String summary;
  final String? artworkUrl;

  String get effectiveTitle =>
      displayTitle.trim().isNotEmpty ? displayTitle : title;

  @override
  bool operator ==(Object other) =>
      other is PlaybackMediaItem &&
      id == other.id &&
      title == other.title &&
      displayTitle == other.displayTitle &&
      summary == other.summary &&
      artworkUrl == other.artworkUrl;

  @override
  int get hashCode => Object.hash(id, title, displayTitle, summary, artworkUrl);
}
```

`LegacyPlaybackMediaItemAdapter` 必须读取所有旧字段值以消费二进制流，但只映射字段 `0`、`2`、`3`、`4`、`8.large`；写入时仍使用这些已发布编号：

```dart
final class LegacyPlaybackMediaItemAdapter
    extends TypeAdapter<PlaybackMediaItem> {
  @override
  final int typeId = 0;

  @override
  PlaybackMediaItem read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, Object?>{
      for (var index = 0; index < count; index++)
        reader.readByte(): reader.read(),
    };
    final images = fields[8];
    final artwork = images is Map ? images['large']?.toString() : null;
    return PlaybackMediaItem(
      id: fields[0] is num ? (fields[0] as num).toInt() : 0,
      title: fields[2]?.toString() ?? '',
      displayTitle: fields[3]?.toString() ?? fields[2]?.toString() ?? '',
      summary: fields[4]?.toString() ?? '',
      artworkUrl: artwork?.trim().isEmpty == true ? null : artwork,
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackMediaItem value) {
    writer
      ..writeByte(5)
      ..writeByte(0)..write(value.id)
      ..writeByte(2)..write(value.title)
      ..writeByte(3)..write(value.displayTitle)
      ..writeByte(4)..write(value.summary)
      ..writeByte(8)..write(<String, String>{
        if (value.artworkUrl != null) 'large': value.artworkUrl!,
      });
  }
}
```

`LegacyBangumiTag` 和其适配器只读取旧字段 `0/1/2`，不提供 JSON 或网络功能：

```dart
// 仅用于旧 Hive 二进制兼容，活动业务不得引用。
final class LegacyBangumiTag {
  const LegacyBangumiTag({
    required this.name,
    required this.count,
    required this.totalCount,
  });
  final String name;
  final int count;
  final int totalCount;
}

final class LegacyBangumiTagAdapter extends TypeAdapter<LegacyBangumiTag> {
  @override
  final int typeId = 4;

  @override
  LegacyBangumiTag read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, Object?>{
      for (var index = 0; index < count; index++)
        reader.readByte(): reader.read(),
    };
    return LegacyBangumiTag(
      name: fields[0]?.toString() ?? '',
      count: fields[1] is num ? (fields[1] as num).toInt() : 0,
      totalCount: fields[2] is num ? (fields[2] as num).toInt() : 0,
    );
  }

  @override
  void write(BinaryWriter writer, LegacyBangumiTag value) {
    writer
      ..writeByte(3)
      ..writeByte(0)..write(value.name)
      ..writeByte(1)..write(value.count)
      ..writeByte(2)..write(value.totalCount);
  }
}
```

- [ ] **Step 5: 替换活动播放链命名**

按以下一一映射修改所有声明、构造参数和调用点：

```text
BangumiItem                  -> PlaybackMediaItem
bangumiItem                  -> mediaItem
PlaybackInitParams.bangumiId -> PlaybackInitParams.mediaId
PlaybackInitParams.bangumiName -> PlaybackInitParams.mediaTitle
PlayerController.bangumiId   -> PlayerController.mediaId
LocalPlaybackRequest.pluginName -> LocalPlaybackRequest.sourceLabel
PlaybackInitParams.pluginName -> PlaybackInitParams.sourceLabel
_buildBangumiItem            -> _buildMediaItem
_buildCloudBangumiItem       -> _buildCloudMediaItem
```

删除 `PlaybackInitParams.adBlockerEnabled`、构造/复制/刷新链上的同名参数以及 `PlayerConfiguration(adBlocker: ...)`；本地与个人网盘播放不再携带旧规则插件的广告过滤开关。同步把 `local_playback_request_builder_test.dart` 的 `pluginName` 断言改为 `sourceLabel`，并更新 `cloud_playback_resolver_test.dart` 中的 `PlaybackInitParams` 夹具。

`PlayerItem` 的媒体会话更新改为：

```dart
final mediaItem = videoPageController.mediaItem;
await _audioController.updateSession(
  mediaId: '${mediaItem.id}_${currentRoad}_$currentEpisode',
  title: mediaItem.effectiveTitle,
  artUri: Uri.tryParse(mediaItem.artworkUrl ?? ''),
  // 其余播放状态参数保持原值
);
```

`GStorage.init()` 注册：

```dart
Hive.registerAdapter(LegacyPlaybackMediaItemAdapter());
Hive.registerAdapter(LegacyBangumiTagAdapter());
```

删除旧模型、生成文件和 Bangumi API JSON 测试；不得复用 typeId 0/4 给其他不兼容对象。

- [ ] **Step 6: 运行 Hive、播放请求和播放器参数测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\legacy_playback_media_item_adapter_test.dart test\local_playback_request_builder_test.dart test\local_video_controller_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交活动模型重命名和 Hive 兼容**

```powershell
git add lib/legacy/hive lib/modules/video/playback_media_item.dart lib/utils/storage.dart lib/modules/video/local_playback_request.dart lib/services/local_playback_request_builder.dart lib/pages/video/video_page_controller_interface.dart lib/pages/video/local_video_controller.dart lib/pages/player/player_controller.dart lib/pages/player/player_item.dart test/legacy_playback_media_item_adapter_test.dart
git add -u lib/modules/bangumi test/bangumi_item_from_json_test.dart
git commit -m "重构：使用中性播放模型并保留旧 Hive 兼容"
```

### Task 7: 将活动批量匹配和旧在线残留改为 TMDB 语义

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_controller.g.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/services/local_poster_scraper.dart`
- Modify: `lib/utils/constants.dart`
- Modify: `lib/utils/proxy_manager.dart`
- Modify: `lib/utils/storage.dart`
- Modify: `test/local_only_settings_test.dart`

- [ ] **Step 1: 扩展活动源码旧项目残留守卫**

在 `local_only_settings_test.dart` 加入：

```dart
test('活动源码不再使用旧项目命名或在线能力', () {
  final offenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (path.startsWith('lib/legacy/')) continue;
    final source = entity.readAsStringSync();
    for (final token in const <String>[
      'BangumiItem',
      'matchWithBangumi',
      'isMatchingBangumi',
      'bangumiMatchProgress',
      'bangumiHTTPHeader',
      'bgm.tv',
      'clearWebviewLog',
      'Bangumi fallback',
      'pluginName',
      'adBlockerEnabled',
    ]) {
      if (source.contains(token)) offenders.add('$path: $token');
    }
  }
  expect(offenders, isEmpty, reason: offenders.join('\n'));
});
```

- [ ] **Step 2: 运行守卫并确认旧命名仍存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_only_settings_test.dart`

Expected: FAIL，列出本地控制器、播放器调试函数、常量和注释中的旧命名。

- [ ] **Step 3: 统一 TMDB 和媒体语义**

按以下映射修改 `local_controller.dart` 和 `local_page.dart`：

```text
matchWithBangumi       -> scrapeTmdbMetadata
isMatchingBangumi      -> isScrapingTmdb
bangumiMatchProgress   -> tmdbScrapeProgress
bangumiMatchCurrent    -> tmdbScrapeCurrent
bangumiMatchTotal      -> tmdbScrapeTotal
_BangumiSummaryBlock   -> _MediaSummaryBlock
```

将自动触发改为显式等待并记录错误：

```dart
unawaited(scrapeTmdbMetadata().then((matched) {
  if (matched > 0) {
    AppLogger().i('LocalController: auto-scraped $matched series with TMDB');
  }
}));
```

将 `clearWebviewLog()` 改为 `clearPlayerLog()`；删除 `bangumiHTTPHeader`；将本地海报 scraper 注释和日志改为“索引/TMDB 备用海报”；将代理注释改为 TMDB 在线元数据探测。

从 `SettingBoxKey` 删除无调用的旧在线键：

```dart
searchEnhanceEnable,
autoUpdate,
alwaysOntop,
enableGitProxy,
isWideScreen,
webDavEnable,
webDavEnableHistory,
webDavEnableCollect,
webDavURL,
webDavUsername,
webDavPassword,
searchNotShowWatchedBangumis,
searchNotShowAbandonedBangumis,
timelineNotShowAbandonedBangumis,
timelineNotShowWatchedBangumis,
timelineOnlyShowWatchingBangumis,
bangumiSyncEnable,
bangumiAccessToken,
bangumiSyncPriority,
bangumiImmediateSyncToastEnable,
syncPlayEndPoint,
playerLogLevel,
forceAdBlocker,
proxyTestUrl,
showRating,
downloadParallelEpisodes,
downloadParallelSegments,
```

同时从 `constants.dart` 删除无人调用的 `defaultSyncPlayEndPoints`、`defaultSyncPlayEndPoint` 和 `bangumiHTTPHeader`；保留生成普通 HTTP 请求头仍在使用的 `acceptLanguageList`。

- [ ] **Step 4: 重新生成 MobX 文件**

Run: `D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`

Expected: exit 0，`local_controller.g.dart` 与 `player_controller.g.dart` 使用新字段名，不手工编辑生成器逻辑。

- [ ] **Step 5: 运行本地媒体库和残留守卫测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_only_settings_test.dart test\local_controller_test.dart test\local_library_metadata_coordinator_test.dart test\local_poster_scraper_test.dart`

Expected: PASS；活动源码中的旧名称只允许出现在 `lib/legacy/` 和旧 JSON 兼容解析器。

- [ ] **Step 6: 提交 TMDB 语义清理**

```powershell
git add lib/pages/local/local_controller.dart lib/pages/local/local_controller.g.dart lib/pages/local/local_page.dart lib/pages/video/video_page.dart lib/services/local_poster_scraper.dart lib/utils/constants.dart lib/utils/proxy_manager.dart lib/utils/storage.dart test/local_only_settings_test.dart
git commit -m "重构：统一本地媒体 TMDB 语义"
```

### Task 8: 实现 Anime4K 纯判定策略

**Files:**
- Create: `lib/features/player/application/anime4k_policy.dart`
- Create: `test/anime4k_policy_test.dart`

- [ ] **Step 1: 写尺寸、适配方式和兼容性的失败测试**

新建测试：

```dart
void main() {
  const policy = Anime4kPolicy();

  test('关闭档始终清空着色器', () {
    expect(policy.evaluate(const Anime4kPolicyInput(
      preference: Anime4kPreference.off,
      sourceWidth: 1280,
      sourceHeight: 720,
      outputWidth: 1920,
      outputHeight: 1080,
      fit: Anime4kFit.contain,
      shaderSupported: true,
    )).action, Anime4kAction.clear);
  });

  test('尺寸未就绪时等待且不启用', () {
    final decision = policy.evaluate(const Anime4kPolicyInput(
      preference: Anime4kPreference.quality,
      sourceWidth: 0,
      sourceHeight: 0,
      outputWidth: 1920,
      outputHeight: 1080,
      fit: Anime4kFit.contain,
      shaderSupported: true,
    ));
    expect(decision.state, Anime4kRuntimeState.waitingForSize);
    expect(decision.action, Anime4kAction.clear);
  });

  test('contain 放大超过百分之五才启用效率档', () {
    Anime4kDecision decide(double width) => policy.evaluate(Anime4kPolicyInput(
      preference: Anime4kPreference.efficiency,
      sourceWidth: 1920,
      sourceHeight: 1080,
      outputWidth: width,
      outputHeight: width * 9 / 16,
      fit: Anime4kFit.contain,
      shaderSupported: true,
    ));
    expect(decide(2016).state, Anime4kRuntimeState.notNeeded);
    expect(decide(2017).action, Anime4kAction.enableEfficiency);
  });

  test('cover 和 fill 任一方向明显放大时启用', () {
    for (final fit in <Anime4kFit>[Anime4kFit.cover, Anime4kFit.fill]) {
      final decision = policy.evaluate(Anime4kPolicyInput(
        preference: Anime4kPreference.quality,
        sourceWidth: 1920,
        sourceHeight: 1080,
        outputWidth: 1280,
        outputHeight: 1200,
        fit: fit,
        shaderSupported: true,
      ));
      expect(decision.action, Anime4kAction.enableQuality, reason: fit.name);
    }
  });

  test('渲染器不支持 GLSL 时报告不兼容', () {
    final decision = policy.evaluate(const Anime4kPolicyInput(
      preference: Anime4kPreference.quality,
      sourceWidth: 1280,
      sourceHeight: 720,
      outputWidth: 1920,
      outputHeight: 1080,
      fit: Anime4kFit.contain,
      shaderSupported: false,
    ));
    expect(decision.state, Anime4kRuntimeState.incompatible);
    expect(decision.action, Anime4kAction.clear);
  });
}
```

- [ ] **Step 2: 运行测试并确认策略类型不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_policy_test.dart`

Expected: FAIL，找不到策略文件和枚举。

- [ ] **Step 3: 实现强类型策略**

`anime4k_policy.dart` 完整定义为：

```dart
import 'dart:math';

enum Anime4kPreference { off, efficiency, quality }
enum Anime4kRuntimeState {
  off,
  waitingForSize,
  notNeeded,
  loading,
  efficiencyActive,
  qualityActive,
  failedDisabled,
  incompatible,
}
enum Anime4kFit { contain, cover, fill }
enum Anime4kAction { clear, enableEfficiency, enableQuality }

final class Anime4kPolicyInput {
  const Anime4kPolicyInput({
    required this.preference,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.outputWidth,
    required this.outputHeight,
    required this.fit,
    required this.shaderSupported,
  });

  final Anime4kPreference preference;
  final double sourceWidth;
  final double sourceHeight;
  final double outputWidth;
  final double outputHeight;
  final Anime4kFit fit;
  final bool shaderSupported;
}

final class Anime4kDecision {
  const Anime4kDecision({
    required this.state,
    required this.action,
    required this.scale,
  });

  final Anime4kRuntimeState state;
  final Anime4kAction action;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is Anime4kDecision &&
      state == other.state &&
      action == other.action &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(state, action, scale);
}

final class Anime4kPolicy {
  const Anime4kPolicy();

  Anime4kDecision evaluate(Anime4kPolicyInput input) {
    if (input.preference == Anime4kPreference.off) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.off,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    if (!input.shaderSupported) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.incompatible,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    if (input.sourceWidth <= 0 ||
        input.sourceHeight <= 0 ||
        input.outputWidth <= 0 ||
        input.outputHeight <= 0) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.waitingForSize,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    final widthScale = input.outputWidth / input.sourceWidth;
    final heightScale = input.outputHeight / input.sourceHeight;
    final scale = switch (input.fit) {
      Anime4kFit.contain => min(widthScale, heightScale),
      Anime4kFit.cover || Anime4kFit.fill => max(widthScale, heightScale),
    };
    if (scale <= 1.05) {
      return Anime4kDecision(
        state: Anime4kRuntimeState.notNeeded,
        action: Anime4kAction.clear,
        scale: scale,
      );
    }
    return Anime4kDecision(
      state: input.preference == Anime4kPreference.efficiency
          ? Anime4kRuntimeState.efficiencyActive
          : Anime4kRuntimeState.qualityActive,
      action: input.preference == Anime4kPreference.efficiency
          ? Anime4kAction.enableEfficiency
          : Anime4kAction.enableQuality,
      scale: scale,
    );
  }
}
```

关闭、缺尺寸、不兼容都返回 `clear`；超过阈值时按用户档位返回效率或质量 action。

- [ ] **Step 4: 运行策略测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_policy_test.dart`

Expected: PASS，包括恰好 5% 不启用、超过 5% 启用。

- [ ] **Step 5: 提交策略层**

```powershell
git add lib/features/player/application/anime4k_policy.dart test/anime4k_policy_test.dart
git commit -m "功能：增加 Anime4K 自适应判定策略"
```

### Task 9: 封装 Anime4K mpv 命令和失败清空

**Files:**
- Create: `lib/features/player/application/anime4k_shader_executor.dart`
- Create: `test/anime4k_shader_executor_test.dart`

- [ ] **Step 1: 写设置、清空和失败恢复测试**

```dart
void main() {
  test('效率档以 set 命令加载完整路径列表', () async {
    final commands = <List<String>>[];
    final executor = Anime4kShaderExecutor(
      command: (command) async => commands.add(command),
    );
    await executor.apply(
      Anime4kAction.enableEfficiency,
      shaderPaths: const <String>['a.glsl', 'b.glsl'],
    );
    expect(commands.single, <String>[
      'change-list', 'glsl-shaders', 'set', 'a.glsl;b.glsl',
    ]);
  });

  test('关闭使用 clr 命令', () async {
    final commands = <List<String>>[];
    final executor = Anime4kShaderExecutor(
      command: (command) async => commands.add(command),
    );
    await executor.apply(Anime4kAction.clear);
    expect(commands.single, <String>['change-list', 'glsl-shaders', 'clr', '']);
  });

  test('加载失败后尝试清空并重新抛出原错误', () async {
    final commands = <List<String>>[];
    final error = StateError('shader failed');
    final executor = Anime4kShaderExecutor(command: (command) async {
      commands.add(command);
      if (command[2] == 'set') throw error;
    });

    await expectLater(
      executor.apply(
        Anime4kAction.enableQuality,
        shaderPaths: const <String>['quality.glsl'],
      ),
      throwsA(same(error)),
    );
    expect(commands.last[2], 'clr');
  });
}
```

- [ ] **Step 2: 运行测试并确认执行器不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_shader_executor_test.dart`

Expected: FAIL，找不到 `Anime4kShaderExecutor`。

- [ ] **Step 3: 实现可注入命令执行器**

```dart
typedef Anime4kMpvCommand = Future<void> Function(List<String> command);

final class Anime4kShaderExecutor {
  const Anime4kShaderExecutor({required Anime4kMpvCommand command})
      : _command = command;
  final Anime4kMpvCommand _command;

  Future<void> apply(
    Anime4kAction action, {
    List<String> shaderPaths = const <String>[],
  }) async {
    if (action == Anime4kAction.clear) {
      await _clear();
      return;
    }
    try {
      await _command(<String>[
        'change-list',
        'glsl-shaders',
        'set',
        shaderPaths.join(';'),
      ]);
    } on Object catch (error, stackTrace) {
      try {
        await _clear();
      } on Object {
        // 清空失败不能覆盖首次着色器错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _clear() => _command(
        const <String>['change-list', 'glsl-shaders', 'clr', ''],
      );
}
```

- [ ] **Step 4: 运行执行器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_shader_executor_test.dart`

Expected: PASS；质量失败不自动调用效率档。

- [ ] **Step 5: 提交执行器**

```powershell
git add lib/features/player/application/anime4k_shader_executor.dart test/anime4k_shader_executor_test.dart
git commit -m "功能：封装 Anime4K 着色器执行和恢复"
```

### Task 10: 将 Anime4K 策略接入播放器并去重防抖

**Files:**
- Create: `lib/features/player/application/anime4k_coordinator.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_controller.g.dart`
- Modify: `lib/pages/player/player_item_surface.dart`
- Create: `test/anime4k_player_controller_test.dart`

- [ ] **Step 1: 写控制器编排失败测试**

将判定与执行编排提取为控制器可注入的 `Anime4kCoordinator`，测试用 fake command 验证：

```dart
const _qualityUpscaleInput = Anime4kPolicyInput(
  preference: Anime4kPreference.quality,
  sourceWidth: 1280,
  sourceHeight: 720,
  outputWidth: 1920,
  outputHeight: 1080,
  fit: Anime4kFit.contain,
  shaderSupported: true,
);

test('连续相同布局只执行一次效率档命令', () async {
  final commands = <List<String>>[];
  final coordinator = Anime4kCoordinator(
    policy: const Anime4kPolicy(),
    execute: (decision) async => commands.add(<String>[decision.action.name]),
  );
  const input = Anime4kPolicyInput(
    preference: Anime4kPreference.efficiency,
    sourceWidth: 1280,
    sourceHeight: 720,
    outputWidth: 1920,
    outputHeight: 1080,
    fit: Anime4kFit.contain,
    shaderSupported: true,
  );
  await coordinator.evaluateAndApply(input);
  await coordinator.evaluateAndApply(input);
  expect(commands, hasLength(1));
});

test('失败后锁定为关闭直到用户重新选择', () async {
  var calls = 0;
  final coordinator = Anime4kCoordinator(
    policy: const Anime4kPolicy(),
    execute: (_) async {
      calls++;
      throw StateError('gpu');
    },
  );
  final first = await coordinator.evaluateAndApply(_qualityUpscaleInput);
  final second = await coordinator.evaluateAndApply(_qualityUpscaleInput);
  expect(first.state, Anime4kRuntimeState.failedDisabled);
  expect(second.state, Anime4kRuntimeState.failedDisabled);
  expect(calls, 1);
  coordinator.resetFailureLock();
  await coordinator.evaluateAndApply(_qualityUpscaleInput);
  expect(calls, 2);
});
```

- [ ] **Step 2: 运行测试并确认协调器不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_player_controller_test.dart`

Expected: FAIL，找不到协调器或播放器尚未暴露状态。

- [ ] **Step 3: 实现协调器和播放器状态字段**

协调器保存 `_lastAppliedAction` 和 `_failureLocked`；只有 action 变化才执行：

```dart
typedef Anime4kDecisionExecutor = Future<void> Function(
  Anime4kDecision decision,
);

final class Anime4kCoordinator {
  Anime4kCoordinator({
    required Anime4kPolicy policy,
    required Anime4kDecisionExecutor execute,
  })  : _policy = policy,
        _execute = execute;

  final Anime4kPolicy _policy;
  final Anime4kDecisionExecutor _execute;
  Anime4kAction? _lastAppliedAction;
  bool _failureLocked = false;

  Future<Anime4kDecision> evaluateAndApply(
    Anime4kPolicyInput input,
  ) async {
    if (_failureLocked) {
      return const Anime4kDecision(
        state: Anime4kRuntimeState.failedDisabled,
        action: Anime4kAction.clear,
        scale: 0,
      );
    }
    final decision = _policy.evaluate(input);
    if (_lastAppliedAction == decision.action) return decision;
    try {
      await _execute(decision);
      _lastAppliedAction = decision.action;
      return decision;
    } on Object {
      _failureLocked = true;
      _lastAppliedAction = Anime4kAction.clear;
      return Anime4kDecision(
        state: Anime4kRuntimeState.failedDisabled,
        action: Anime4kAction.clear,
        scale: decision.scale,
      );
    }
  }

  void resetFailureLock() {
    _failureLocked = false;
    _lastAppliedAction = null;
  }

  void reset() {
    _failureLocked = false;
    _lastAppliedAction = null;
  }
}
```

播放器增加：

```dart
@observable
Anime4kPreference anime4kPreference = Anime4kPreference.off;

@observable
Anime4kRuntimeState anime4kRuntimeState = Anime4kRuntimeState.off;

Timer? _anime4kLayoutDebounce;
Size _anime4kOutputPixels = Size.zero;
```

原 `superResolutionType` 替换为上述强类型；读取旧整数设置时使用：

```dart
anime4kPreference = switch (setting.getTyped<int>(
  SettingBoxKey.defaultSuperResolutionType,
  defaultValue: 1,
)) {
  2 => Anime4kPreference.efficiency,
  3 => Anime4kPreference.quality,
  _ => Anime4kPreference.off,
};
```

加入布局入口：

```dart
void updateAnime4kOutputSize({
  required Size logicalSize,
  required double devicePixelRatio,
}) {
  final pixels = Size(
    logicalSize.width * devicePixelRatio,
    logicalSize.height * devicePixelRatio,
  );
  if (pixels == _anime4kOutputPixels) return;
  _anime4kOutputPixels = pixels;
  _scheduleAnime4kEvaluation();
}

void _scheduleAnime4kEvaluation() {
  _anime4kLayoutDebounce?.cancel();
  _anime4kLayoutDebounce = Timer(
    const Duration(milliseconds: 250),
    () => unawaited(_evaluateAnime4k()),
  );
}

@action
Future<void> setAnime4kPreference(Anime4kPreference value) async {
  _anime4kLayoutDebounce?.cancel();
  _anime4kCoordinator.resetFailureLock();
  anime4kPreference = value;
  await _evaluateAnime4k();
}
```

源宽高订阅、初始化完成和用户档位变化都调用调度。画面比例只通过以下 action 修改，两个 panel 原有的直接赋值都替换为此方法：

```dart
@action
void setAspectRatioType(int value) {
  if (aspectRatioType == value) return;
  aspectRatioType = value;
  _scheduleAnime4kEvaluation();
}
```

`dispose`/播放器资源释放时取消 timer 并清空协调器状态。

- [ ] **Step 4: 使用执行器应用决策且失败不阻断播放**

在 `PlayerController` 中构造协调器，并由一个入口统一更新运行状态：

```dart
late final Anime4kCoordinator _anime4kCoordinator = Anime4kCoordinator(
  policy: const Anime4kPolicy(),
  execute: _executeAnime4kDecision,
);

Future<void> _evaluateAnime4k() async {
  final decision = await _anime4kCoordinator.evaluateAndApply(
    Anime4kPolicyInput(
      preference: anime4kPreference,
      sourceWidth: playerWidth.toDouble(),
      sourceHeight: playerHeight.toDouble(),
      outputWidth: _anime4kOutputPixels.width,
      outputHeight: _anime4kOutputPixels.height,
      fit: switch (aspectRatioType) {
        2 => Anime4kFit.cover,
        3 => Anime4kFit.fill,
        _ => Anime4kFit.contain,
      },
      shaderSupported: mediaPlayer?.platform is NativePlayer,
    ),
  );
  anime4kRuntimeState = decision.state;
}
```

执行回调等待 `NativePlayer` 初始化；需要启用时先设置 `loading`，清空时不显示加载状态。用 `mpvAnime4KShadersLite` 或 `mpvAnime4KShaders` 映射出 Windows 绝对路径列表：

```dart
Future<void> _executeAnime4kDecision(Anime4kDecision decision) async {
  final platform = mediaPlayer?.platform;
  if (platform is! NativePlayer) return;
  final stopwatch = Stopwatch()..start();
  var shaderCount = 0;
  await platform.waitForPlayerInitialization;
  await platform.waitForVideoControllerInitializationIfAttached;
  final executor = Anime4kShaderExecutor(command: platform.command);
  try {
    if (decision.action == Anime4kAction.clear) {
      await executor.apply(Anime4kAction.clear);
      return;
    }
    anime4kRuntimeState = Anime4kRuntimeState.loading;
    final names = decision.action == Anime4kAction.enableEfficiency
        ? mpvAnime4KShadersLite
        : mpvAnime4KShaders;
    final shaderPaths = names
        .map((name) => p.join(shadersController.shadersDirectory.path, name))
        .toList(growable: false);
    shaderCount = shaderPaths.length;
    await executor.apply(
      decision.action,
      shaderPaths: shaderPaths,
    );
  } on Object catch (error, stackTrace) {
    AppLogger().w(
      'Anime4K: disabled after load failure '
      'preference=${anime4kPreference.name} '
      'source=${playerWidth}x$playerHeight '
      'output=${_anime4kOutputPixels.width.round()}x${_anime4kOutputPixels.height.round()} '
      'shaders=$shaderCount elapsedMs=${stopwatch.elapsedMilliseconds}',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  } finally {
    stopwatch.stop();
    AppLogger().i(
      'Anime4K: apply finished '
      'preference=${anime4kPreference.name} '
      'action=${decision.action.name} '
      'source=${playerWidth}x$playerHeight '
      'output=${_anime4kOutputPixels.width.round()}x${_anime4kOutputPixels.height.round()} '
      'shaders=$shaderCount elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
  }
}
```

成功后 `_evaluateAnime4k` 更新 active/notNeeded/off；异常日志只记录尺寸、档位、着色器数量和耗时，不记录媒体路径，并重新抛给协调器转为失败状态。`createVideoController` 不再直接 `await setShader()`；初始化默认档位只调度 `_evaluateAnime4k()`，任何 Anime4K 异常不得从视频初始化路径抛出。

- [ ] **Step 5: 在播放表面传入物理输出尺寸**

将 `Video` 所在区域包在 `LayoutBuilder` 中：

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    playerController.updateAnime4kOutputSize(
      logicalSize: constraints.biggest,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return Stack(children: <Widget>[
      Video(
        controller: videoController,
        controls: null,
        pauseUponEnteringBackgroundMode: false,
        fit: playerController.aspectRatioType == 1
            ? BoxFit.contain
            : playerController.aspectRatioType == 2
                ? BoxFit.cover
                : BoxFit.fill,
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: false,
        ),
      ),
      if (showSubtitle)
        Positioned.fill(
          child: _PrimarySubtitleView(
            controller: videoController,
            textStyle: subtitleTextStyle,
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              subtitlePaddingBottom,
            ),
          ),
        ),
    ]);
  },
);
```

- [ ] **Step 6: 重新生成 MobX 并运行策略、执行器、控制器测试**

Run: `D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`

Expected: exit 0。

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_policy_test.dart test\anime4k_shader_executor_test.dart test\anime4k_player_controller_test.dart test\player_subtitle_render_strategy_test.dart`

Expected: PASS；相同决策不重复调用，布局变化需经过 250ms。

- [ ] **Step 7: 提交播放器接入**

```powershell
git add lib/features/player/application/anime4k_coordinator.dart lib/pages/player/player_controller.dart lib/pages/player/player_controller.g.dart lib/pages/player/player_item_surface.dart test/anime4k_player_controller_test.dart
git commit -m "功能：播放器自适应启用 Anime4K"
```

### Task 11: 显示 Anime4K 用户选择与实际状态

**Files:**
- Create: `lib/pages/player/widgets/anime4k_status_label.dart`
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/smallest_player_item_panel.dart`
- Modify: `lib/pages/settings/super_resolution_settings.dart`
- Create: `test/anime4k_player_ui_test.dart`

- [ ] **Step 1: 写状态文案和高亮语义失败测试**

```dart
void main() {
  testWidgets('已选择质量档但无需放大时显示当前未启用', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Anime4kStatusLabel(
          preference: Anime4kPreference.quality,
          runtimeState: Anime4kRuntimeState.notNeeded,
        ),
      ),
    ));
    expect(find.text('质量档（当前未启用）'), findsOneWidget);
  });

  testWidgets('加载失败不显示已启用文案', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Anime4kStatusLabel(
          preference: Anime4kPreference.quality,
          runtimeState: Anime4kRuntimeState.failedDisabled,
        ),
      ),
    ));
    expect(find.text('质量档（加载失败，已关闭）'), findsOneWidget);
    expect(find.textContaining('已启用'), findsNothing);
  });
}
```

- [ ] **Step 2: 运行 UI 测试并确认状态组件不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_player_ui_test.dart`

Expected: FAIL，找不到 `Anime4kStatusLabel`。

- [ ] **Step 3: 实现统一状态文案组件**

组件文案映射必须完整：

```dart
String anime4kStatusText(
  Anime4kPreference preference,
  Anime4kRuntimeState state,
) {
  final selected = switch (preference) {
    Anime4kPreference.off => '关闭',
    Anime4kPreference.efficiency => '效率档',
    Anime4kPreference.quality => '质量档',
  };
  return switch (state) {
    Anime4kRuntimeState.off => '关闭',
    Anime4kRuntimeState.waitingForSize => '$selected（等待画面尺寸）',
    Anime4kRuntimeState.notNeeded => '$selected（当前未启用）',
    Anime4kRuntimeState.loading => '$selected（正在加载）',
    Anime4kRuntimeState.efficiencyActive => '效率档（已启用）',
    Anime4kRuntimeState.qualityActive => '质量档（已启用）',
    Anime4kRuntimeState.failedDisabled => '$selected（加载失败，已关闭）',
    Anime4kRuntimeState.incompatible => '$selected（当前渲染器不兼容）',
  };
}

class Anime4kStatusLabel extends StatelessWidget {
  const Anime4kStatusLabel({
    super.key,
    required this.preference,
    required this.runtimeState,
    this.style,
  });

  final Anime4kPreference preference;
  final Anime4kRuntimeState runtimeState;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
        anime4kStatusText(preference, runtimeState),
        style: style,
      );
}
```

`Anime4kStatusLabel` 只渲染 `Text`，不增加新的菜单层级或动画。

- [ ] **Step 4: 两套播放器菜单全部 await 并区分选择/运行状态**

将菜单回调改为：

```dart
onPressed: () async {
  await widget.handleSuperResolutionChange(
    Anime4kPreference.values[index],
  );
},
```

高亮只表示用户选择 `anime4kPreference`；submenu 标题使用 `Anime4kStatusLabel` 显示当前实际状态。`PlayerItem.handleSuperResolutionChange` 保留质量档首次性能提示，但删除 Android renderer 检查，并必须：

```dart
await playerController.setAnime4kPreference(preference);
```

`PlayerItem` 增加自己的 `_anime4kFailureShown` 和 MobX reaction；监听 `failedDisabled`，当尚未提示时提示一次：

```dart
late final ReactionDisposer _anime4kStateReaction;
bool _anime4kFailureShown = false;

_anime4kStateReaction = mobx.reaction<Anime4kRuntimeState>(
  (_) => playerController.anime4kRuntimeState,
  (state) {
    if (state != Anime4kRuntimeState.failedDisabled ||
        _anime4kFailureShown ||
        !_canUsePlayer) {
      return;
    }
    _anime4kFailureShown = true;
    AppDialog.showToast(message: '当前显卡或渲染器无法启用超分辨率');
  },
);
```

`dispose` 调用 `_anime4kStateReaction()`；用户重新选择非关闭档位前把 `_anime4kFailureShown = false`，而 `setAnime4kPreference` 重置协调器失败锁。不自动降级效率档。

- [ ] **Step 5: 更新设置页 Windows 文案和强类型映射**

设置页保留底层整数存储兼容，但 UI 文案改为：

- 关闭：不使用 Anime4K。
- 效率档：需要放大时自动启用轻量 Anime4K。
- 质量档：需要放大时自动启用完整 Anime4K，显卡负载更高。
- 说明：窗口缩小或原始分辨率足够时会暂时关闭，不会更改默认选择。

删除“尝试切换视频渲染器为 gpu”等 Android 文案。

- [ ] **Step 6: 运行 UI、播放器和设置测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\anime4k_player_ui_test.dart test\settings_ui_residue_test.dart test\player_overlay_coordinator_test.dart`

Expected: PASS；失败状态没有错误高亮为“已启用”。

- [ ] **Step 7: 提交 Anime4K 状态反馈**

```powershell
git add lib/pages/player/widgets/anime4k_status_label.dart lib/pages/player/player_item.dart lib/pages/player/player_item_panel.dart lib/pages/player/smallest_player_item_panel.dart lib/pages/settings/super_resolution_settings.dart test/anime4k_player_ui_test.dart
git commit -m "优化：显示 Anime4K 实际运行状态"
```

### Task 12: 完成依赖、生成文件和全量源码守卫

**Files:**
- Modify: `test/windows_only_residue_test.dart`
- Modify: `test/local_only_settings_test.dart`
- Modify: `pubspec.lock`
- Modify (generated): `lib/pages/local/local_controller.g.dart`
- Modify (generated): `lib/pages/player/player_controller.g.dart`
- Modify (generated): `windows/flutter/generated_plugin_registrant.cc`
- Modify (generated): `windows/flutter/generated_plugins.cmake`

- [ ] **Step 1: 给生成插件和旧能力增加最终断言**

在 `windows_only_residue_test.dart` 增加：

```dart
test('Windows 插件注册不含已删除插件', () {
  final generated = <String>[
    File('windows/flutter/generated_plugin_registrant.cc').readAsStringSync(),
    File('windows/flutter/generated_plugins.cmake').readAsStringSync(),
  ].join('\n');
  for (final token in const <String>[
    'dynamic_color',
    'flutter_displaymode',
    'saver_gallery',
    'screen_brightness',
    'audio_service_mpris',
  ]) {
    expect(generated, isNot(contains(token)), reason: token);
  }
});
```

在旧能力守卫中检查活动源码不含 `WebView`、规则插件、公共在线影视搜索和在线评论路由；允许 `README.md` 解释产品边界，不扫描文档。

- [ ] **Step 2: 重新生成依赖和代码**

Run: `D:\flutter\bin\flutter.bat pub get`

Expected: exit 0。

Run: `D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`

Expected: exit 0。

- [ ] **Step 3: 运行三组全部定向测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\settings_ui_residue_test.dart test\windows_only_residue_test.dart test\local_only_settings_test.dart test\local_media_index_tmdb_test.dart test\legacy_playback_media_item_adapter_test.dart test\anime4k_policy_test.dart test\anime4k_shader_executor_test.dart test\anime4k_player_controller_test.dart test\anime4k_player_ui_test.dart`

Expected: PASS。

- [ ] **Step 4: 运行静态分析并清除所有错误**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`；不能通过新增全局 ignore 绕过错误。

- [ ] **Step 5: 检查关键 diff 并提交生成收尾**

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake lib/pages/local/local_controller.g.dart lib/pages/player/player_controller.g.dart
git add pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake lib/pages/local/local_controller.g.dart lib/pages/player/player_controller.g.dart test/windows_only_residue_test.dart test/local_only_settings_test.dart
git commit -m "测试：固化 Windows 专属工程边界"
```

Expected: 只出现本阶段相关差异，生成注册中保留 `audio_service_win`、`flutter_volume_controller`、`media_kit_libs_windows_video` 等 Windows 插件。

### Task 13: 递增版本并更新用户发布资料

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 再次记录当前已安装版本状态**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName
```

Expected: 本轮开始时无输出，记录为“当前未安装”；若执行时已有安装，则以实际输出为准并记录，不能从 `pubspec.yaml` 推断。

- [ ] **Step 2: 先修改版本一致性测试为新版本并确认失败**

在 `version_consistency_test.dart` 修改：

```dart
const expectedVersion = '2.1.48';
const expectedBuildNumber = '20148';

for (final feature in <String>[
  '夸克',
  '百度',
  'Windows',
  'Anime4K',
  '媒体库',
  '播放器',
]) {
  expect(copy, contains(feature));
}
```

把旧的 `['夸克', '转存', '扫描', '媒体库', '播放器']` 特征循环替换为上面的新列表，并将通用安全断言从 `contains('不会修改')` 改为 `contains('不会修改或删除')`。在 `identity_v2_zero_residue_test.dart` 将 `expect(currentVersion, '2.1.47')` 改为 `2.1.48`。在 `version_history_current_test.dart` 新增：

```dart
test('二点一四十八收敛 Windows 网盘入口和 Anime4K', () {
  final entries = versionHistoryForCurrent('2.1.48');
  expect(entries, hasLength(1));
  final changes = entries.single.changes.join('\n');
  expect(entries.single.isPrerelease, isTrue);
  expect(changes, contains('百度'));
  expect(changes, contains('Windows'));
  expect(changes, contains('Anime4K'));
  expect(changes, contains('不会修改或删除'));
});
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart`

Expected: FAIL，当前仍为 2.1.47。

- [ ] **Step 3: 同步版本和面向普通用户的文案**

修改：

```yaml
version: 2.1.48+20148
msix_config:
  msix_version: 2.1.48.0
```

`AppVersion.current` 改为 `2.1.48`。发布说明首项使用以下一致内容，不复制开发术语：

```text
- 网盘媒体库现在可直接添加夸克和百度网盘，添加完成后会自动刷新并切换到新来源；OpenList 仍可在来源管理中使用，并继续标注为调试中。
- 看影音已进一步收敛为 Windows 专属应用，移除了不会在 Windows 使用的移动端设置、插件和资源，保留本地媒体、个人网盘、字幕、选集、全屏、画中画和硬件解码。
- Anime4K 只在画面确实需要放大时启用；窗口缩小或原始分辨率足够时会暂时关闭，加载失败也不会中断视频播放。
- 旧版媒体索引和播放数据仍可读取，迁移失败只会丢弃无效旧元数据，不会修改或删除本地或网盘中的原始视频。
- 没有 TMDB Key、断网或 TMDB 暂时不可用时，本地与网盘扫描和播放仍可继续使用。
```

README 同步将“视频渲染器选择、低延迟音频”改为 Windows 实际能力，并说明 Anime4K 自适应；不得写“播放器 Anime4K 行为保持不变”。

- [ ] **Step 4: 运行版本和文档一致性测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交版本资料**

```powershell
git add pubspec.yaml lib/core/app_version.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md lib/utils/version_history.dart test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "发布：准备 2.1.48 测试版"
```

### Task 14: 完整验证、签名 MSIX、桌面交付和最终提交

**Files:**
- Verify: `build/windows/x64/runner/Release/`
- Verify: generated `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `%USERPROFILE%\Desktop\看影音-2.1.48.msix`
- Deliver: `%USERPROFILE%\Desktop\看影音-2.1.48-异机安装包.zip`

- [ ] **Step 1: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部 PASS，退出码 0。

- [ ] **Step 2: 运行完整静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 3: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit 0，存在且非空：

```text
build/windows/x64/runner/Release/kanyingyin.exe
build/windows/x64/runner/Release/data/app.so
```

- [ ] **Step 4: 检查 Release 插件和资产没有被清理项**

Run:

```powershell
$release = 'build\windows\x64\runner\Release'
$forbidden = 'dynamic_color|flutter_displaymode|saver_gallery|screen_brightness|audio_service_mpris|logo_android|logo_ios|assets\\linux'
Get-ChildItem -LiteralPath $release -Recurse -File | Where-Object { $_.FullName -match $forbidden }
```

Expected: 无输出。再确认 `data/flutter_assets/assets/shaders` 中 Anime4K GLSL 文件存在。

- [ ] **Step 5: 生成并验证签名 MSIX**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 脚本完成 Release、MSIX 生成、SHA256 签名验证、清单身份/架构/版本验证，并复制：

```text
%USERPROFILE%\Desktop\看影音-2.1.48.msix
%USERPROFILE%\Desktop\看影音-2.1.48-异机安装包.zip
```

- [ ] **Step 6: 独立核对桌面包清单和签名**

Run:

```powershell
$msix = Join-Path $env:USERPROFILE 'Desktop\看影音-2.1.48.msix'
Get-Item -LiteralPath $msix | Select-Object FullName,Length,LastWriteTime
Get-AuthenticodeSignature -LiteralPath $msix | Select-Object Status,StatusMessage,SignerCertificate
```

Expected: 文件非空，签名 `Status` 为 `Valid`。解包读取 `AppxManifest.xml` 后确认：

```text
Identity Name = com.kanyingyin.player
Identity Version = 2.1.48.0
ProcessorArchitecture = x64
DisplayName = 看影音
```

- [ ] **Step 7: 若执行安装则再次查询已安装版本**

只有用户或既定测试流程实际安装 MSIX 时才执行：

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName
```

Expected: `Version` 为 `2.1.48.0`。未安装则明确记录“本轮未执行安装”，不能声称已安装。

- [ ] **Step 8: 最终检查只提交本轮相关文件**

```powershell
git status --short
git diff --check
git log -8 --oneline
```

Expected: 构建目录、MSIX、ZIP、证书和密码文件均未进入 Git；设计文档和本实施计划属于本轮资料，应纳入提交。

- [ ] **Step 9: 提交验证中产生的必要修正和计划文档**

```powershell
git add docs/superpowers/specs/2026-07-24-windows-only-cleanup-and-cloud-onboarding-design.md docs/superpowers/plans/2026-07-24-windows-cleanup-cloud-onboarding-anime4k.md
git diff --name-only --diff-filter=AM
git commit -m "交付：完成 Windows 专属 2.1.48 测试版"
```

如果 `git diff --name-only --diff-filter=AM` 还列出验证阶段修正的本轮文件，先逐个执行 `git add -p 文件路径` 审阅并暂存；没有额外修正则只提交两份计划文档。不能执行 `git add .`。

Expected: 工作区只剩用户原有或明确不属于本轮的改动；若 `.git/index.lock` 因当前沙箱只读而失败，保留全部工作区改动并明确报告，不能伪称已提交。

## 计划完成标准

- 网盘媒体库空状态和常驻菜单只直接推荐夸克、百度；OpenList 留在来源管理并标注调试中。
- 新来源保存成功后返回 ID、刷新来源并优先选中；刷新失败保留原索引和选中来源。
- 活动 Windows 代码、设置、依赖、插件注册和资产不再携带移动端/Linux/macOS/Web 实现。
- `flutter_volume_controller` 与 `audio_session` 因 Windows 播放调用保留；其余明确无 Windows 调用路径的依赖移除。
- 当前索引不再写 `bangumi*` 字段，旧 JSON/Hive 仍可只读迁移；任何兼容失败不丢视频索引。
- 活动模型和批量刮削使用媒体/TMDB 语义，旧名称只存在于隔离兼容层。
- Anime4K 仅在实际放大超过 5% 时启用，250ms 防抖，相同 action 不重复执行；失败后清空、继续播放、不自动降档并只提示一次。
- `flutter test --no-pub`、`flutter analyze --no-pub`、Windows Release 和签名 MSIX 全部通过。
- 应用版本 `2.1.48+20148`、MSIX `2.1.48.0`、发布资料一致，桌面存在有效签名的 `看影音-2.1.48.msix`。
