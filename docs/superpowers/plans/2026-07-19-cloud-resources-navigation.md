# 网盘资源主导航实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在“本地”上方新增“网盘资源”主导航，让用户直接浏览已启用的 OpenList 和夸克目录并播放视频。

**Architecture:** 新增独立 `CloudResourcesModule` / `CloudResourcesPage` / `CloudResourcesController`，通过现有 `CloudProviderRegistry` 和安全凭据存储访问远程目录。目录浏览使用 `CloudRemoteRef`，播放复用 `CloudPlaybackResolver` 与 `LocalVideoController`，删除复用 `CloudLibraryController.delete()`。

**Tech Stack:** Flutter 3.41.9、Flutter Modular、ChangeNotifier、MobX 现有主导航、media-kit 现有播放流程、flutter_test、MSIX 3.18.0。

---

## 文件结构

- 新增 `lib/pages/cloud/resources/cloud_resources_controller.dart`：来源、目录、搜索、导航栈与乱序请求保护。
- 新增 `lib/pages/cloud/resources/cloud_resources_page.dart`：网盘页面组合与播放/移除交互。
- 新增 `lib/pages/cloud/resources/cloud_resources_grid.dart`：文件夹和视频的纯展示网格。
- 新增 `lib/pages/cloud/resources/cloud_resources_module.dart`：`/tab/cloud/` 路由。
- 修改 `lib/pages/navigation/navigation_config.dart`：主导航增加网盘资源。
- 修改 `lib/pages/index_module.dart`：注入网盘资源控制器的生产依赖。
- 新增 `test/cloud_resources_controller_test.dart`、`test/cloud_resources_page_test.dart`，修改 `test/navigation_config_test.dart`。

### Task 1: 主导航与独立路由

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resources_module.dart`
- Modify: `lib/pages/navigation/navigation_config.dart`
- Modify: `test/navigation_config_test.dart`

- [ ] **Step 1: 先写失败导航测试**

将断言改为：

```dart
expect(appNavigationDestinations.map((item) => item.label), [
  '网盘资源',
  '本地',
  '我的',
]);
expect(appNavigationDestinations.first.path, '/cloud');
expect(isValidStartupPage('/tab/cloud/'), isTrue);
expect(navigationIndexForStartupPage('/tab/local/'), 1);
expect(defaultStartupPage, '/tab/local/');
```

- [ ] **Step 2: 运行红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\navigation_config_test.dart`

Expected: FAIL，因导航仍只有“本地、我的”。

- [ ] **Step 3: 新增模块并注册导航**

```dart
class CloudResourcesModule extends Module {
  @override
  void routes(r) {
    r.child('/', child: (_) => const CloudResourcesPage());
  }
}
```

```dart
NavigationDestinationConfig(
  path: '/cloud',
  label: '网盘资源',
  icon: Icons.cloud_outlined,
  selectedIcon: Icons.cloud,
  moduleBuilder: CloudResourcesModule.new,
),
```

该配置放在“本地”前，`defaultStartupPage` 仍为 `/tab/local/`。为保证路由可编译，此阶段先创建最小 `CloudResourcesPage` 空页，Task 3 再替换为完整页面。

- [ ] **Step 4: 运行绿灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\navigation_config_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/pages/navigation/navigation_config.dart lib/pages/cloud/resources/cloud_resources_module.dart lib/pages/cloud/resources/cloud_resources_page.dart test/navigation_config_test.dart
git commit -m '界面：新增网盘资源主导航'
```

### Task 2: 强类型网盘目录控制器

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Create: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 先写来源与根目录失败测试**

```dart
test('只显示已启用来源且单根目录直接加载', () async {
  final controller = CloudResourcesController(
    repository: repository,
    credentialStore: credentials,
    providerRegistry: registry,
  );
  await controller.load();
  expect(controller.sources.map((source) => source.id), ['quark-enabled']);
  expect(client.listed.single,
      const CloudRemoteRef(id: 'root-fid', path: '/影视'));
  expect(controller.currentDirectory?.id, 'root-fid');
});

test('多根目录先显示虚拟根页', () async {
  await controller.load();
  expect(controller.isVirtualRoot, isTrue);
  expect(controller.entries.map((entry) => entry.id), ['root-a', 'root-b']);
  expect(client.listed, isEmpty);
});
```

- [ ] **Step 2: 运行红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart`

Expected: FAIL，`CloudResourcesController` 尚不存在。

- [ ] **Step 3: 实现最小控制器**

```dart
class CloudResourcesController extends ChangeNotifier {
  CloudResourcesController({
    required CloudSourceRepository repository,
    required CloudCredentialStore credentialStore,
    CloudProviderRegistry? providerRegistry,
  })  : _repository = repository,
        _credentialStore = credentialStore,
        _providerRegistry = providerRegistry ?? CloudProviderRegistry();

  final CloudSourceRepository _repository;
  final CloudCredentialStore _credentialStore;
  final CloudProviderRegistry _providerRegistry;
  final List<CloudRemoteRef> _history = <CloudRemoteRef>[];
  List<CloudSource> sources = <CloudSource>[];
  List<CloudFileEntry> entries = <CloudFileEntry>[];
  CloudSource? selectedSource;
  CloudRemoteRef? currentDirectory;
  bool isVirtualRoot = false;
  bool loading = false;
  String query = '';
  String? errorMessage;
  int _generation = 0;

  Future<void> load() async {
    sources = (await _repository.getAll())
        .where((source) => source.enabled)
        .toList(growable: false);
    await selectSource(sources.firstOrNull?.id);
  }
}
```

`selectSource()` 对单根目录调用 `_loadDirectory(root)`，对多根目录用 `CloudFileEntry` 组成虚拟根页。每次请求通过注册器创建客户端并在 `finally` 中 `close()`。

- [ ] **Step 4: 增加目录、搜索与乱序测试**

```dart
test('进入目录、返回上级和搜索保留强类型引用', () async {
  await controller.openDirectory(
    const CloudRemoteRef(id: 'child-fid', path: '/影视/动漫'),
  );
  controller.setQuery('剧场版');
  expect(controller.visibleEntries.single.name, contains('剧场版'));
  await controller.goBack();
  expect(controller.currentDirectory?.id, 'root-fid');
});

test('慢响应不会覆盖新来源', () async {
  final oldRequest = controller.selectSource('slow');
  await controller.selectSource('fast');
  slowClient.complete();
  await oldRequest;
  expect(controller.selectedSource?.id, 'fast');
  expect(controller.entries.single.name, '新目录');
});
```

- [ ] **Step 5: 实现导航栈、视频过滤和错误映射**

`visibleEntries` 只保留文件夹或 `LocalVideoFileTypes.isVideoPath(entry.name)` 为真的条目，文件夹在前，再按名称排序。捕获 `CloudDriveException` 时使用 `_providerRegistry.errorMessage(source.type, error)`，其他异常映射为“网盘目录加载失败”。

- [ ] **Step 6: 运行全部控制器测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart`

Expected: PASS。

```powershell
git add lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
git commit -m '功能：实现网盘目录浏览状态'
```

### Task 3: 网盘资源页面

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resources_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `lib/pages/index_module.dart`
- Create: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 先写页面空状态和目录失败测试**

```dart
testWidgets('无来源时显示两种添加入口', (tester) async {
  await tester.pumpWidget(testApp(controller));
  await tester.pumpAndSettle();
  expect(find.text('还没有可用的网盘来源'), findsOneWidget);
  expect(find.text('添加 OpenList'), findsOneWidget);
  expect(find.text('添加夸克网盘'), findsOneWidget);
});

testWidgets('显示来源、文件夹和视频且不显示字幕', (tester) async {
  await tester.pumpWidget(testApp(controller));
  await tester.pumpAndSettle();
  expect(find.text('夸克媒体库'), findsOneWidget);
  expect(find.text('动漫'), findsOneWidget);
  expect(find.text('第01集.mkv'), findsOneWidget);
  expect(find.text('第01集.ass'), findsNothing);
});
```

- [ ] **Step 2: 运行红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，空页尚无所需组件。

- [ ] **Step 3: 实现页面与网格**

`CloudResourcesPage` 从 Modular 取共享控制器，也支持测试注入。顶部工具栏包含来源菜单、管理来源、移除来源、返回上级、刷新和路径；下方为搜索框与响应式网格。

```dart
CloudResourcesGrid(
  entries: controller.visibleEntries,
  onOpenDirectory: (entry) => controller.openDirectory(
    CloudRemoteRef(id: entry.id, path: entry.remotePath),
  ),
  onPlay: _play,
)
```

`CloudResourcesGrid` 使用 `LayoutBuilder` 在窄宽度显示 2 列，桌面宽度按最小卡片宽度增加列数。文件夹使用文件夹图标，视频卡显示名称、大小和修改时间。

- [ ] **Step 4: 注入控制器生产依赖**

```dart
i.addSingleton<CloudResourcesController>(() => CloudResourcesController(
      repository: Modular.get<CloudSourceRepository>(),
      credentialStore: Modular.get<CloudCredentialStore>(),
    ));
```

- [ ] **Step 5: 运行页面测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\navigation_config_test.dart`

Expected: PASS。

```powershell
git add lib/pages/cloud/resources lib/pages/index_module.dart test/cloud_resources_page_test.dart
git commit -m '界面：实现网盘资源浏览页'
```

### Task 4: 播放、来源移除与管理入口

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 先写播放目标失败测试**

```dart
testWidgets('点击视频使用来源 ID 和远程 ID 播放', (tester) async {
  CloudPlaybackTarget? target;
  await tester.pumpWidget(testApp(
    controller,
    onPlay: (value) async => target = value,
  ));
  await tester.tap(find.text('第01集.mkv'));
  await tester.pump();
  expect(target?.sourceId, 'quark-source');
  expect(target?.remoteId, 'video-fid');
  expect(target?.remotePath, '/影视/第01集.mkv');
});
```

- [ ] **Step 2: 先写安全移除失败测试**

```dart
testWidgets('移除来源先提示不删除远程文件', (tester) async {
  await tester.tap(find.byTooltip('移除当前来源'));
  await tester.pumpAndSettle();
  expect(find.textContaining('不会删除网盘中的任何文件'), findsOneWidget);
  await tester.tap(find.text('移除'));
  await tester.pumpAndSettle();
  expect(deletedSourceId, 'quark-source');
});
```

- [ ] **Step 3: 运行红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，播放与移除回调尚未实现。

- [ ] **Step 4: 复用现有播放与删除流程**

```dart
final target = CloudPlaybackTarget(
  sourceId: source.id,
  remoteId: entry.id,
  remotePath: entry.remotePath,
  stableId: '${source.id}:${entry.id}:${entry.remotePath}',
  title: entry.name,
);
await localVideoController.openCloudPlayback(
  seriesTitle: entry.name,
  targets: <CloudPlaybackTarget>[target],
  selectedStableId: target.stableId,
  resolver: playbackResolver.resolve,
);
Modular.to.pushNamed('/video/');
```

移除确认后调用注入的 `CloudLibraryController.delete(source.id)`，然后 `controller.load()`。“管理来源”导航到 `/settings/cloud-sources`。

- [ ] **Step 5: 运行绿灯并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_playback_resolver_test.dart test\cloud_source_cleanup_test.dart`

Expected: PASS。

```powershell
git add lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m '功能：接入网盘目录播放与安全移除'
```

### Task 5: 回归、版本与 MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 完整质量门禁**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 格式无变化，全量测试通过，analyze 无错误。

- [ ] **Step 2: 更新版本与用户文案**

更新为：

```yaml
version: 2.1.5+20105
msix_version: 2.1.5.0
```

版本历史和更新说明明确写入“新增网盘资源主导航”、“可浏览 OpenList 与夸克目录”、“点击视频可在线播放”和“移除来源不删除远程文件”。

- [ ] **Step 3: 版本后重跑完整门禁与 Release**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 全部退出码为 0，`kanyingyin.exe` 和 `data/app.so` 为本轮产物。

- [ ] **Step 4: 生成并签名 MSIX**

本机 `msix 3.18.0` 不允许 CLI `true` 覆盖 YAML `sign_msix: false`，因此仅在打包期间用 `apply_patch` 临时改为 `true`，使用 `%USERPROFILE%\.kanyingyin\signing\certificate.pfx` 和 DPAPI 密码生成签名包，随后用 `apply_patch` 恢复为 `false`。密码只存在 PowerShell 内存变量。

- [ ] **Step 5: 验证清单、签名和桌面产物**

验证：

```text
Identity Name: com.kanyingyin.player
Identity Version: 2.1.5.0
Architecture: x64
Authenticode Status: Valid
AppxSignature.p7x: 存在
Desktop: C:\Users\asus\Desktop\看影音-2.1.5.msix
```

计算 SHA-256，并确认桌面包签名仍为 `Valid`。

- [ ] **Step 6: 检查差异并提交发布**

```powershell
git status --short
git diff --check
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m '发布：交付网盘资源导航 2.1.5'
```

`.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 始终保持未暂存、未提交。
