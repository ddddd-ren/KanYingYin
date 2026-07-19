# 网盘资源自动批量整理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增用户主动触发的来源级递归 TMDB 整理，将高置信度中文标题应用为看影音显示名，同时绝不修改网盘文件。

**Architecture:** 新建纯扫描服务，通过 `CloudDriveClient.listDirectory` 发现作品候选；`CloudResourcesController` 负责客户端生命周期、缓存跳过、TMDB 提交和汇总；页面只负责确认、进度和结果展示。既有单项刮削、当前目录刮削和后台调度保持兼容。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、Flutter Modular、flutter_test、Windows Release、MSIX

---

### Task 1：递归发现可整理的网盘作品

**Files:**
- Create: `lib/services/cloud/cloud_resource_auto_organizer.dart`
- Create: `test/cloud_resource_auto_organizer_test.dart`

- [ ] **Step 1：写失败测试覆盖候选分类**

创建假客户端目录树：根目录包含独立电影、电影文件夹、分类目录和剧集目录；电影文件夹直接含视频，剧集目录含“第一季”，分类目录继续向下。断言：

```dart
final result = await const CloudResourceAutoOrganizer().discover(
  source: source,
  client: client,
);
expect(
  result.candidates.map((item) => item.displayName),
  containsAll(<String>['根目录电影.mkv', '电影文件夹', '剧集名称', '分类中的电影']),
);
expect(result.candidates.map((item) => item.displayName),
    isNot(contains('第一季')));
expect(result.candidates.map((item) => item.displayName),
    isNot(contains('电影文件.mkv')));
```

新增多根目录、重复远程引用、单分支读取失败继续、全部根失败抛错、1000 目录和 20 层限制测试。

- [ ] **Step 2：运行测试确认类型不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_auto_organizer_test.dart`

Expected: FAIL，提示扫描服务和结果类型不存在。

- [ ] **Step 3：实现扫描类型和队列遍历**

公开接口固定为：

```dart
typedef CloudResourceAutoScanProgress = void Function(
  int scannedDirectories,
  int discoveredCandidates,
);

class CloudResourceAutoOrganizeDiscovery {
  const CloudResourceAutoOrganizeDiscovery({
    required this.candidates,
    required this.scannedDirectories,
    required this.failedDirectories,
  });
  final List<CloudResourceTmdbTarget> candidates;
  final int scannedDirectories;
  final int failedDirectories;
}

class CloudResourceAutoOrganizer {
  const CloudResourceAutoOrganizer({
    this.maximumDirectories = 1000,
    this.maximumDepth = 20,
  });
  final int maximumDirectories;
  final int maximumDepth;

  Future<CloudResourceAutoOrganizeDiscovery> discover({
    required CloudSource source,
    required CloudDriveClient client,
    CloudResourceAutoScanProgress? onProgress,
  });
}
```

队列节点保存 `CloudRemoteRef`、深度和 `isConfiguredRoot`。根目录视频生成 `standaloneVideo` 候选；非根目录有直接视频或季目录时生成 `directory` 候选并停止下钻；普通分类目录继续入队。季目录识别 `第一季`、`Season 1`、`S01`。稳定键去重，单目录异常计数并继续；所有根失败抛 `CloudDriveException`。

- [ ] **Step 4：格式化并运行扫描测试**

Run: `D:\flutter\bin\dart.bat format lib\services\cloud\cloud_resource_auto_organizer.dart test\cloud_resource_auto_organizer_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_auto_organizer_test.dart`

Expected: PASS。

- [ ] **Step 5：提交扫描服务**

```powershell
git add -- lib/services/cloud/cloud_resource_auto_organizer.dart test/cloud_resource_auto_organizer_test.dart
git commit -m "功能：递归发现网盘影视资源"
```

### Task 2：控制器执行来源级 TMDB 整理

**Files:**
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1：写失败测试覆盖跳过、汇总和安全边界**

新增成功、待确认、无结果、单项失败的录制 coordinator；断言：

```dart
final summary = await fixture.controller.autoOrganizeSelectedSource(
  onProgress: progress.add,
);
expect(summary.matched, 1);
expect(summary.pending, 1);
expect(summary.noResult, 1);
expect(summary.failed, 1);
expect(progress.last.completedTargets, 4);
```

预置 matched 和七天内 unmatched 记录，断言两者计入 `skipped` 且未调用 scrape。无 API Key 时断言在任何 `listDirectory` 前抛出“请先在设置中填写 TMDB API Key”。后台刮削进行时拒绝并提示稍后重试。

- [ ] **Step 2：运行控制器测试确认 API 不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_controller_test.dart`

Expected: FAIL，提示自动整理方法、进度和汇总类型不存在。

- [ ] **Step 3：实现 coordinator 能力查询与控制器类型**

coordinator 新增：

```dart
bool get hasApiKey => _apiKeyProvider().trim().isNotEmpty;
```

控制器文件新增：

```dart
enum CloudResourceAutoOrganizePhase { scanning, scraping }

class CloudResourceAutoOrganizeProgress {
  const CloudResourceAutoOrganizeProgress({
    required this.phase,
    required this.scannedDirectories,
    required this.discoveredTargets,
    required this.completedTargets,
    required this.totalTargets,
  });
  final CloudResourceAutoOrganizePhase phase;
  final int scannedDirectories;
  final int discoveredTargets;
  final int completedTargets;
  final int totalTargets;
}

class CloudResourceAutoOrganizeSummary {
  const CloudResourceAutoOrganizeSummary({
    required this.matched,
    required this.pending,
    required this.noResult,
    required this.failed,
    required this.skipped,
  });
  final int matched;
  final int pending;
  final int noResult;
  final int failed;
  final int skipped;
}
```

- [ ] **Step 4：实现 `autoOrganizeSelectedSource`**

方法先校验来源、coordinator、API Key 和 `isScraping`，创建一个客户端并在 `finally` 关闭。调用扫描服务后按记录过滤：同名 matched 跳过；同名且七天内 unmatched 跳过；其余顺序调用 `coordinator.scrape`。根据 outcome 统计 matched/pending/noResult，异常只增加 failed。每项完成都回调 scraping 进度，最后返回 summary。

- [ ] **Step 5：运行控制器和 coordinator 测试**

Run: `D:\flutter\bin\dart.bat format lib\services\cloud\cloud_resource_tmdb_coordinator.dart lib\pages\cloud\resources\cloud_resources_controller.dart test\cloud_resources_controller_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_controller_test.dart test\cloud_resource_tmdb_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 6：提交控制器编排**

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
git commit -m "功能：批量整理网盘来源元数据"
```

### Task 3：页面入口、确认、进度和结果

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写页面失败测试**

新增测试点击 tooltip `自动整理当前来源`，确认弹窗必须显示“不会修改网盘文件”；取消不调用控制器，确认后显示扫描/整理进度和汇总：

```dart
expect(find.textContaining('不会修改网盘文件'), findsOneWidget);
await tester.tap(find.widgetWithText(FilledButton, '开始整理'));
await tester.pumpAndSettle();
expect(find.textContaining('成功 1 项'), findsOneWidget);
expect(find.textContaining('待确认 1 项'), findsOneWidget);
```

整理期间按钮、来源切换、刷新和当前目录刮削禁用，播放卡片保持可操作。

- [ ] **Step 2：运行页面测试确认入口不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart`

Expected: FAIL，找不到自动整理入口。

- [ ] **Step 3：实现确认和执行方法**

页面新增 `_autoOrganizing` 和 `_autoOrganizeProgress`。`_confirmAutoOrganize` 弹窗列出当前来源名称、递归范围、安全边界；确认后调用 controller，进度回调在 mounted 时 setState；完成 snackbar 文案为：

```text
自动整理完成：成功 X 项，待确认 X 项，无结果 X 项，失败 X 项，已跳过 X 项
```

错误复用 TMDB API Key 提示，目录限制与读取失败显示明确文案，finally 清理运行状态。

- [ ] **Step 4：接入工具栏和进度条**

工具栏新增 `Icons.auto_awesome_motion_outlined` 按钮，tooltip 为“自动整理当前来源”。进度区域 scanning 显示“正在扫描目录 N，已发现 M 项”，scraping 显示“正在整理 X/Y”。运行期间禁用来源选择、两个刮削按钮、刷新和移除来源。

- [ ] **Step 5：运行页面及播放回归**

Run: `D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resources_page.dart test\cloud_resources_page_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart test\quark_drive_client_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 6：提交页面功能**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "界面：加入网盘自动批量整理"
```

### Task 4：更新 2.1.14 并完成交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1：同步版本和文案**

版本固定为 `2.1.14+20114`、MSIX `2.1.14.0`。文案说明来源级递归整理、进度/汇总、歧义保持原名和不修改网盘文件。

- [ ] **Step 2：运行版本测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart`

Expected: PASS。

```powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "发布：更新看影音 2.1.14 文案"
```

- [ ] **Step 3：完整验证**

Run: `D:\flutter\bin\flutter.bat test`

Run: `D:\flutter\bin\flutter.bat analyze`

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: 全量测试 PASS，分析 `No issues found!`，Release 生成成功。

- [ ] **Step 4：生成、签名和验证 MSIX**

Run: `D:\flutter\bin\dart.bat run msix:create --build-windows false`

使用本机 `CN=KanYingYin` 私钥签名，验证包标识 `com.kanyingyin.player`、版本 `2.1.14.0`、架构 x64 和签名 `Valid`，复制为 `C:\Users\asus\Desktop\看影音-2.1.14.msix` 并报告 SHA-256。

## 自查

- 规格中的递归分类、限制、跳过、进度、汇总、安全边界和交付均有对应任务。
- 所有新公开类型和方法在首次使用前已定义，名称在各任务中一致。
- 不调用远程写入接口，不修改网盘名称、路径或播放逻辑。
- 用户禁止子智能体，因此后续固定使用 inline execution。
