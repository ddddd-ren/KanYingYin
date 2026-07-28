# 网盘海报墙隐藏视频实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在网盘海报卡菜单中允许精确隐藏某个真实视频版本，并提供持久化、恢复和来源删除清理能力。

**Architecture:** 使用独立 `CloudHiddenVideoRepository` 保存来源级隐藏记录，扫描索引保持完整；`CloudResourcesController` 仅在构造海报墙集合前过滤隐藏条目。海报墙暴露“隐藏视频”动作，页面负责单版本确认、多版本选择和隐藏管理对话框，所有远程文件保持不变。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、ChangeNotifier、Hive CE、`synchronized`、`flutter_test`、Windows MSIX。

---

## 文件结构

- 新建 `lib/modules/cloud/cloud_hidden_video.dart`：隐藏记录值对象、稳定匹配规则和远程路径规范化。
- 新建 `lib/repositories/cloud_hidden_video_repository.dart`：Hive/内存存储、按来源替换和清理隐藏记录。
- 新建 `lib/pages/cloud/resources/cloud_hidden_video_dialogs.dart`：单/多版本隐藏选择和已隐藏视频管理界面。
- 修改 `lib/pages/cloud/resources/cloud_resources_controller.dart`：加载、过滤、隐藏和恢复状态。
- 修改 `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：资源菜单增加“隐藏视频”动作。
- 修改 `lib/pages/cloud/resources/cloud_resources_page.dart`：连接菜单、对话框、提示和管理入口。
- 修改 `lib/features/cloud/application/cloud_resources_toolbar.dart`：管理入口的可用状态。
- 修改 `lib/providers/cloud_library_controller.dart`：来源移除成功后清理隐藏记录。
- 修改 `lib/app/bindings/cloud_bindings.dart`：注册并复用隐藏记录仓库。
- 修改 `lib/features/settings/application/typed_settings.dart`：增加独立 Hive 键。
- 新建/修改对应测试文件，最后更新 2.1.64 测试版文档和版本配置。

### Task 1：隐藏记录模型与持久化仓库

**Files:**
- Create: `lib/modules/cloud/cloud_hidden_video.dart`
- Create: `lib/repositories/cloud_hidden_video_repository.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`
- Test: `test/cloud_hidden_video_repository_test.dart`

- [ ] **Step 1：先写仓库失败测试**

新增以下核心用例：

```dart
test('隐藏记录按来源持久化并可跨仓库实例读取', () async {
  final storage = MemoryCloudHiddenVideoStorage();
  final first = CloudHiddenVideoRepository(storage: storage);
  await first.replaceSource('source-a', <CloudHiddenVideo>[
    const CloudHiddenVideo(
      sourceId: 'source-a',
      remoteId: 'video-b',
      remotePath: '/电影/B.mkv',
      fileName: 'B.mkv',
    ),
  ]);

  final second = CloudHiddenVideoRepository(storage: storage);
  expect(await second.getBySource('source-a'), hasLength(1));
  expect(await second.getBySource('source-b'), isEmpty);
});

test('损坏记录被忽略且清理来源不影响其他来源', () async {
  final storage = MemoryCloudHiddenVideoStorage(<Object?>[
    <String, Object?>{'sourceId': 'source-a'},
    <String, Object?>{
      'sourceId': 'source-b',
      'remoteId': 'b',
      'remotePath': '/B.mkv',
      'fileName': 'B.mkv',
    },
  ]);
  final repository = CloudHiddenVideoRepository(storage: storage);
  expect(await repository.getBySource('source-a'), isEmpty);
  await repository.clearSource('source-a');
  expect(await repository.getBySource('source-b'), hasLength(1));
});
```

- [ ] **Step 2：运行测试并确认因类型不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_repository_test.dart
```

Expected: FAIL，提示 `CloudHiddenVideo`、`CloudHiddenVideoRepository` 或内存存储未定义。

- [ ] **Step 3：实现最小模型和仓库**

模型提供明确的匹配 API：

```dart
class CloudHiddenVideo {
  const CloudHiddenVideo({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.fileName,
  });

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final String fileName;

  factory CloudHiddenVideo.fromEntry({
    required String sourceId,
    required CloudFileEntry entry,
  }) => CloudHiddenVideo(
        sourceId: sourceId,
        remoteId: entry.id,
        remotePath: entry.remotePath,
        fileName: entry.name,
      );

  bool matches({
    required String sourceId,
    required String remoteId,
    required String remotePath,
  }) {
    if (this.sourceId != sourceId) return false;
    if (this.remoteId.isNotEmpty && remoteId.isNotEmpty) {
      return this.remoteId == remoteId;
    }
    return normalizeCloudHiddenVideoPath(this.remotePath) ==
        normalizeCloudHiddenVideoPath(remotePath);
  }
}
```

仓库接口固定为：

```dart
abstract interface class ICloudHiddenVideoRepository {
  Future<List<CloudHiddenVideo>> getBySource(String sourceId);
  Future<void> replaceSource(
    String sourceId,
    List<CloudHiddenVideo> records,
  );
  Future<void> clearSource(String sourceId);
}
```

Hive 存储使用新键 `SettingBoxKey.cloudPosterHiddenVideos`。`replaceSource` 在同一个 `synchronized` 锁中读取全部记录、替换目标来源并写回；解析时逐条捕获格式错误。

- [ ] **Step 4：运行仓库测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_repository_test.dart
```

Expected: PASS，全部仓库测试通过。

- [ ] **Step 5：提交仓库层**

```powershell
git add lib/modules/cloud/cloud_hidden_video.dart lib/repositories/cloud_hidden_video_repository.dart lib/features/settings/application/typed_settings.dart test/cloud_hidden_video_repository_test.dart
git commit -m "新增网盘隐藏视频存储"
```

### Task 2：控制器过滤、隐藏、恢复和扫描保持

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Test: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1：先写 A/B 版本过滤失败测试**

测试使用 `MemoryCloudHiddenVideoStorage` 和真实仓库，建立同作品 A、B 两个索引项：

```dart
test('隐藏 B 版本后海报集合保留 A 且底层索引完整', () async {
  final hiddenRepository = CloudHiddenVideoRepository(
    storage: MemoryCloudHiddenVideoStorage(),
  );
  final controller = CloudResourcesController(
    repository: sourceRepository,
    credentialStore: credentialStore,
    mediaIndexRepository: mediaIndexRepository,
    hiddenVideoRepository: hiddenRepository,
    workTmdbCoordinator: workCoordinator,
    providerRegistry: providerRegistry,
  );
  await controller.load();
  final group = controller.collection.groups.single;
  final versionB = group.videos.singleWhere((entry) => entry.id == 'b');

  await controller.hideVideos(<CloudFileEntry>[versionB]);

  expect(controller.collection.groups.single.videos, hasLength(1));
  expect(controller.collection.groups.single.videos.single.id, 'a');
  expect(await mediaIndexRepository.getBySource('source-a'), hasLength(2));
});
```

再增加三个独立用例：隐藏唯一视频后卡片消失且恢复后立即出现；重新选择来源/重新加载索引后隐藏仍生效；仓库写入抛错时集合和 `hiddenVideos` 均不变化。

- [ ] **Step 2：运行控制器测试并确认缺少 API**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_controller_test.dart
```

Expected: FAIL，提示构造参数 `hiddenVideoRepository`、`hideVideos` 或恢复 API 不存在。

- [ ] **Step 3：实现控制器最小行为**

增加以下状态和公开接口：

```dart
final ICloudHiddenVideoRepository _hiddenVideoRepository;
List<CloudHiddenVideo> _hiddenVideos = <CloudHiddenVideo>[];

List<CloudHiddenVideo> get hiddenVideos =>
    List<CloudHiddenVideo>.unmodifiable(_hiddenVideos);

Future<void> hideVideos(Iterable<CloudFileEntry> videos);
Future<void> restoreHiddenVideo(CloudHiddenVideo record);
Future<void> restoreAllHiddenVideos();
```

`_selectSource` 清空旧隐藏状态，并在当前 generation 下读取新来源记录。读取失败时使用空列表、继续加载媒体，并设置非阻断错误文案“隐藏视频设置读取失败，已显示全部视频”。

`visibleIndexedItems` 和兼容 `entries` 分组路径都调用同一匹配函数：

```dart
bool _isHidden({
  required String sourceId,
  required String remoteId,
  required String remotePath,
}) => _hiddenVideos.any(
      (record) => record.matches(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
      ),
    );
```

隐藏/恢复方法先构造不可变新列表并 `await replaceSource`，写入成功后才替换 `_hiddenVideos` 和通知监听器；失败直接抛出，不能提前改变界面。

- [ ] **Step 4：运行控制器测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_controller_test.dart
```

Expected: PASS，原控制器用例和新增隐藏用例全部通过。

- [ ] **Step 5：提交控制器行为**

```powershell
git add lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
git commit -m "支持网盘视频隐藏与恢复"
```

### Task 3：海报卡菜单和精确版本选择

**Files:**
- Create: `lib/pages/cloud/resources/cloud_hidden_video_dialogs.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Test: `test/cloud_hidden_video_dialogs_test.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：先写菜单和多版本选择失败测试**

海报墙测试传入 `onHide`，打开三点菜单并断言：

```dart
await tester.tap(find.byTooltip('资源操作'));
await tester.pumpAndSettle();
expect(find.text('隐藏视频'), findsOneWidget);
await tester.tap(find.text('隐藏视频'));
expect(hiddenGroup, same(group));
```

对话框测试传入 A、B 两个 `CloudFileEntry`，勾选 B 并确认：

```dart
await tester.tap(find.byKey(const ValueKey<String>('hide-video-b')));
await tester.tap(find.widgetWithText(FilledButton, '隐藏所选'));
await tester.pumpAndSettle();
expect(result.map((entry) => entry.id), <String>['b']);
```

页面集成测试确认选择 B 后控制器集合只剩 A，并出现“已隐藏 1 个视频”提示。

- [ ] **Step 2：运行 UI 测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_page_test.dart
```

Expected: FAIL，提示 `onHide`、隐藏菜单或对话框函数不存在。

- [ ] **Step 3：实现菜单与选择对话框**

`CloudResourcePosterWall` 增加可空回调：

```dart
final CloudResourceGroupAction? onHide;
```

当回调存在时，在“媒体详情”后增加分隔线和菜单项：

```dart
const PopupMenuDivider(),
const PopupMenuItem(
  value: _ResourceAction.hide,
  child: Text('隐藏视频'),
),
```

单视频对话框返回确认后的单项列表；多视频对话框用 `StatefulBuilder` 保存 `Set<String>`，每行以远程 ID 构造稳定 `ValueKey`，展示名称、`variantLabel` 和远程路径，按钮只有在集合非空时可用。

页面方法固定为：

```dart
Future<void> _hideVideos(CloudResourceMediaGroup group) async {
  final selected = await showCloudHideVideoDialog(
    context: context,
    videos: group.videos,
  );
  if (selected == null || selected.isEmpty || !mounted) return;
  try {
    await _controller.hideVideos(selected);
    if (mounted) _showMessage('已隐藏 ${selected.length} 个视频');
  } on Object {
    if (mounted) _showMessage('隐藏设置保存失败，请重试');
  }
}
```

- [ ] **Step 4：运行 UI 测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_page_test.dart
```

Expected: PASS，菜单、单版本确认、多版本选择和页面集成用例通过。

- [ ] **Step 5：提交隐藏交互**

```powershell
git add lib/pages/cloud/resources/cloud_hidden_video_dialogs.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_page_test.dart
git commit -m "添加海报卡隐藏视频操作"
```

### Task 4：已隐藏视频管理、空状态和来源清理

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_hidden_video_dialogs.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `lib/features/cloud/application/cloud_resources_toolbar.dart`
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Test: `test/cloud_hidden_video_dialogs_test.dart`
- Test: `test/cloud_resources_toolbar_policy_test.dart`
- Test: `test/cloud_library_controller_test.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：先写恢复管理和清理失败测试**

新增用例：

```dart
testWidgets('管理已隐藏视频可逐个恢复和全部恢复', (tester) async {
  // 打开顶部更多菜单，选择“管理已隐藏视频”。
  // 恢复 B 后列表移除 B，海报集合重新包含 B。
  // 点击“全部恢复”并确认后列表进入空状态。
});

test('扫描期间仍允许管理隐藏视频', () {
  final state = const CloudResourcesToolbarPolicy().evaluate(
    hasSelectedSource: true,
    loading: false,
    scanning: true,
    batchScraping: false,
    autoOrganizing: false,
    tmdbBusy: false,
  );
  expect(state.canManageHiddenVideos, isTrue);
});

test('删除来源后清理该来源隐藏记录且保留其他来源', () async {
  await controller.delete('source-a');
  expect(await hiddenRepository.getBySource('source-a'), isEmpty);
  expect(await hiddenRepository.getBySource('source-b'), hasLength(1));
});
```

另加页面空状态用例：当前集合为空且 `hiddenVideos` 非空时显示“视频已隐藏，可从更多网盘操作中恢复”。

- [ ] **Step 2：运行相关测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_toolbar_policy_test.dart test/cloud_library_controller_test.dart test/cloud_resources_page_test.dart
```

Expected: FAIL，提示管理动作、策略字段、来源清理或空状态尚未实现。

- [ ] **Step 3：实现管理界面和来源清理**

工具栏枚举与状态增加：

```dart
enum CloudToolbarAction {
  manageHiddenVideos,
  autoOrganize,
  scrape,
  removeSource,
}

final bool canManageHiddenVideos;
```

策略值为 `hasSelectedSource && !loading`，因此扫描期间仍可管理。页面菜单把“管理已隐藏视频”放在整理和刮削之前。

管理对话框接收当前记录以及两个异步回调：

```dart
Future<void> Function(CloudHiddenVideo record) onRestore;
Future<void> Function() onRestoreAll;
```

逐个恢复成功后从对话框本地列表移除；全部恢复要求二次确认。任何回调抛错时保留列表并显示“恢复失败，请重试”。

在依赖绑定中注册同一个 `CloudHiddenVideoRepository`，同时注入 `CloudResourcesController` 和 `CloudLibraryController`。来源删除流程在远程来源记录删除成功后调用 `clearSource`；清理失败只显示本地清理警告，不能把已成功删除的来源回滚成存在。

- [ ] **Step 4：运行相关测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_repository_test.dart test/cloud_resources_controller_test.dart test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_toolbar_policy_test.dart test/cloud_library_controller_test.dart test/cloud_resources_page_test.dart
```

Expected: PASS，隐藏、恢复、扫描保持和来源清理全部通过。

- [ ] **Step 5：提交管理和清理行为**

```powershell
git add lib/pages/cloud/resources/cloud_hidden_video_dialogs.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/features/cloud/application/cloud_resources_toolbar.dart lib/providers/cloud_library_controller.dart lib/app/bindings/cloud_bindings.dart test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_toolbar_policy_test.dart test/cloud_library_controller_test.dart test/cloud_resources_page_test.dart
git commit -m "支持管理已隐藏网盘视频"
```

### Task 5：测试版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1：确认版本迭代前已安装版本记录**

已记录：`com.kanyingyin.player 2.1.63.0`。如果执行时系统状态变化，重新运行：

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, PackageFullName, InstallLocation
```

- [ ] **Step 2：先把版本测试期望改为 2.1.64 并确认失败**

把版本一致性测试更新为：应用版本 `2.1.64`、build `20164`、MSIX `2.1.64.0`，版本历史包含“隐藏视频”“恢复”“不会修改或删除网盘文件”。

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
```

Expected: FAIL，实际配置仍为 2.1.63。

- [ ] **Step 3：更新版本和用户文案**

统一更新：

```yaml
version: 2.1.64+20164
msix_version: 2.1.64.0
```

用户文案说明：可以从海报卡隐藏具体版本；可从顶部菜单恢复；重启和重新扫描后保留；不会修改或删除网盘文件。

- [ ] **Step 4：运行版本测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
```

Expected: PASS，版本和文案一致。

- [ ] **Step 5：提交版本更新**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布二点一六十四测试版"
```

### Task 6：全量验证、Windows Release 与 MSIX 交付

**Files:**
- Verify only; build artifacts remain untracked.

- [ ] **Step 1：格式化本轮 Dart 文件并检查差异**

Run:

```powershell
D:\flutter\bin\dart.bat format lib/modules/cloud/cloud_hidden_video.dart lib/repositories/cloud_hidden_video_repository.dart lib/pages/cloud/resources/cloud_hidden_video_dialogs.dart lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/features/cloud/application/cloud_resources_toolbar.dart lib/providers/cloud_library_controller.dart lib/app/bindings/cloud_bindings.dart test/cloud_hidden_video_repository_test.dart test/cloud_resources_controller_test.dart test/cloud_hidden_video_dialogs_test.dart test/cloud_resources_toolbar_policy_test.dart test/cloud_library_controller_test.dart test/cloud_resources_page_test.dart
git diff --check
```

Expected: 格式化成功，`git diff --check` 无输出。

- [ ] **Step 2：运行完整质量门禁**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全部测试通过；静态分析显示 `No issues found!`。

- [ ] **Step 3：构建 Windows Release**

Run:

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: Exit code 0，生成最新 `build\windows\x64\runner\Release\kanyingyin.exe` 和 `data\app.so`。

- [ ] **Step 4：生成签名 MSIX 并复制到桌面**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: SignTool 验证成功，桌面生成：

- `C:\Users\asus\Desktop\看影音-2.1.64.msix`
- `C:\Users\asus\Desktop\看影音-2.1.64-异机安装包.zip`

- [ ] **Step 5：核验清单、签名和安装版本**

读取桌面 MSIX 的 `AppxManifest.xml`，确认：

```text
Name=com.kanyingyin.player
Publisher=CN=KanYingYin
Version=2.1.64.0
ProcessorArchitecture=x64
```

确认 `Get-AuthenticodeSignature` 为 `Valid`，记录 SHA256；随后再次执行 `Get-AppxPackage -Name com.kanyingyin.player`。若打包流程执行了安装，已安装版本必须为 2.1.64.0；若未安装，明确记录现有版本。

- [ ] **Step 6：提交前审计并完成最终提交**

Run:

```powershell
git status --short
git diff --check
git log -6 --oneline
```

只提交本轮相关源码、测试、规格、计划和版本文档。构建目录与桌面安装包不得进入 Git。工作区干净后报告提交记录、测试数量、分析结果、Release 结果、MSIX 路径、签名、清单版本和安装版本。
