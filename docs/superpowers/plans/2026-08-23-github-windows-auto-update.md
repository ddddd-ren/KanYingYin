# GitHub Windows 自动更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为看影音 Windows 版增加每天自动检查 GitHub 正式 Release、手动检查、应用内下载校验并启动 Inno Setup 更新的完整能力。

**Architecture:** 在 `lib/features/app_update/` 内分离版本与 Release 模型、GitHub 数据客户端、检查策略、下载与安装运行时、表现协调和弹窗。启动页和关于页只调用共享更新流程；网络、时钟、设置、临时目录、进程启动与退出均可注入，以便严格执行 TDD。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Dio、crypto、path_provider、Flutter Modular、Hive CE、Inno Setup、GitHub Releases API。

---

## 文件结构

- Create: `lib/features/app_update/domain/app_update_models.dart`
- Create: `lib/features/app_update/data/github_release_client.dart`
- Create: `lib/features/app_update/application/app_update_checker.dart`
- Create: `lib/features/app_update/application/windows_update_installer.dart`
- Create: `lib/features/app_update/presentation/app_update_dialog.dart`
- Create: `lib/features/app_update/presentation/app_update_flow.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`
- Modify: `lib/app/bindings/infrastructure_bindings.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `lib/pages/about/about_page.dart`
- Create: `test/app_update_models_test.dart`
- Create: `test/github_release_client_test.dart`
- Create: `test/app_update_checker_test.dart`
- Create: `test/windows_update_installer_test.dart`
- Create: `test/app_update_dialog_test.dart`
- Create: `test/app_update_flow_test.dart`
- Modify: `test/init_page_test.dart`
- Modify: `test/about_page_content_test.dart`
- Modify: version and release contract files for `2.1.168+20168`.

### Task 1: 语义版本与更新领域模型

**Files:**
- Create: `test/app_update_models_test.dart`
- Create: `lib/features/app_update/domain/app_update_models.dart`

- [ ] **Step 1: 写失败测试**

测试严格解析 `2.1.168` 和 `v2.1.168`，拒绝缺段、前导零、预发布后缀；验证 `2.10.0 > 2.9.99`；验证 Release 只接受名称包含完整版本号的唯一 `.exe` 资产。

```dart
test('严格解析三段版本并按数值排序', () {
  expect(SemanticVersion.parseTag('v2.1.168').toString(), '2.1.168');
  expect(() => SemanticVersion.parseTag('2.1.168'), throwsFormatException);
  expect(() => SemanticVersion.parseTag('v2.1.168-beta'), throwsFormatException);
  expect(
    SemanticVersion.parse('2.10.0'),
    greaterThan(SemanticVersion.parse('2.9.99')),
  );
});
```

- [ ] **Step 2: 运行并观察正确失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_models_test.dart`

Expected: FAIL，原因是 `SemanticVersion` 和领域模型尚不存在。

- [ ] **Step 3: 实现最小领域模型**

```dart
final class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);
  factory SemanticVersion.parse(String source) => _parse(source, false);
  factory SemanticVersion.parseTag(String source) => _parse(source, true);
  final int major;
  final int minor;
  final int patch;

  static SemanticVersion _parse(String source, bool tagged) {
    final pattern = tagged
        ? RegExp(r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
        : RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');
    final match = pattern.firstMatch(source);
    if (match == null) throw FormatException('版本格式无效: $source');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    return minorOrder != 0 ? minorOrder : patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}
```

同文件定义 `AppReleaseAsset(name, size, sha256, downloadUri)`、`AppRelease(version, tagName, name, body, publishedAt, assets)`、`AppUpdateCheckStatus` 和 `AppUpdateCheckResult`。为 `SemanticVersion` 补齐值相等与 `hashCode`。`AppRelease.windowsInstaller` 在候选不唯一时抛出 `StateError`。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_models_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add -- lib/features/app_update/domain/app_update_models.dart test/app_update_models_test.dart
git commit -m "功能：添加自动更新领域模型"
```

### Task 2: GitHub 正式 Release 客户端

**Files:**
- Create: `test/github_release_client_test.dart`
- Create: `lib/features/app_update/data/github_release_client.dart`

- [ ] **Step 1: 写失败测试**

使用项目已有的自定义 Dio `HttpClientAdapter` 测试模式返回固定 JSON。覆盖草稿、预发布和无效标签过滤；按语义版本选择最高正式版而不是按发布时间；解析 `sha256:` 摘要；拒绝摘要无效、无 EXE 和多个 EXE。

```dart
test('选择语义版本最高的非草稿非预发布 Release', () async {
  final client = GitHubReleaseClient(dio: dioReturning(<Object?>[
    releaseJson(tag: 'v2.1.169', draft: true),
    releaseJson(tag: 'v2.1.170', prerelease: true),
    releaseJson(tag: 'invalid'),
    releaseJson(tag: 'v2.10.0'),
    releaseJson(tag: 'v2.9.99'),
  ]));
  expect(
    (await client.fetchLatestStableRelease()).version.toString(),
    '2.10.0',
  );
});
```

- [ ] **Step 2: 运行并观察正确失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/github_release_client_test.dart`

Expected: FAIL，原因是 `GitHubReleaseClient` 尚不存在。

- [ ] **Step 3: 实现客户端**

```dart
class GitHubReleaseClient {
  GitHubReleaseClient({Dio? dio}) : _dio = dio ?? _createDio();
  static final Uri releasesUri = Uri.parse(
    'https://api.github.com/repos/ddddd-ren/KanYingYin/releases?per_page=30',
  );
  final Dio _dio;
  Future<AppRelease> fetchLatestStableRelease();

  static Dio _createDio() => DioFactory.createForConfig(
        const NetworkConfig(
          connectTimeout: Duration(seconds: 12),
          receiveTimeout: Duration(seconds: 20),
        ),
        defaultHeaders: const <String, Object?>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'KanYingYin-App-Updater',
        },
      );
}
```

逐条验证 `tag_name`、`draft`、`prerelease`、`published_at` 和 `assets`。单条无效 Release 被忽略；整体不是列表、没有有效正式版或最高正式版没有唯一可校验的 Windows EXE时抛出明确异常。摘要移除 `sha256:` 前缀并转小写。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/github_release_client_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add -- lib/features/app_update/data/github_release_client.dart test/github_release_client_test.dart
git commit -m "功能：读取 GitHub 正式版本"
```

### Task 3: 版本判断与每日成功节流

**Files:**
- Create: `test/app_update_checker_test.dart`
- Create: `lib/features/app_update/application/app_update_checker.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`

- [ ] **Step 1: 写失败测试**

覆盖远端更高、相等、本地更高；每天成功一次后不再自动请求；失败不写日期；手动流程之后可以写成功日期。

```dart
test('本地测试版高于正式版时拒绝降级', () async {
  final checker = AppUpdateChecker(
    localVersion: SemanticVersion.parse('2.1.167'),
    fetchLatestRelease: () async => release('1.0.8'),
  );
  expect((await checker.check()).status, AppUpdateCheckStatus.localAhead);
});
```

- [ ] **Step 2: 运行并观察正确失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_checker_test.dart`

Expected: FAIL，原因是检查器、策略和设置键不存在。

- [ ] **Step 3: 实现检查器与策略**

```dart
typedef LatestReleaseFetcher = Future<AppRelease> Function();
typedef UpdateClock = DateTime Function();

class AppUpdateChecker {
  const AppUpdateChecker({
    required this.localVersion,
    required LatestReleaseFetcher fetchLatestRelease,
  }) : _fetchLatestRelease = fetchLatestRelease;
  final SemanticVersion localVersion;
  final LatestReleaseFetcher _fetchLatestRelease;
  Future<AppUpdateCheckResult> check() async {
    final release = await _fetchLatestRelease();
    final order = release.version.compareTo(localVersion);
    if (order > 0) return AppUpdateCheckResult.updateAvailable(release);
    if (order < 0) return const AppUpdateCheckResult.localAhead();
    return const AppUpdateCheckResult.upToDate();
  }
}
```

`DailyUpdateCheckPolicy` 接收 `TypedSettings` 和可选时钟，将本地日期格式化为 `yyyy-MM-dd`。`isDue` 读取 `SettingBoxKey.lastSuccessfulUpdateCheckDate`；`markSuccessful()` 写入当天。只由成功检查调用。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_checker_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add -- lib/features/app_update/application/app_update_checker.dart lib/features/settings/application/typed_settings.dart test/app_update_checker_test.dart
git commit -m "功能：添加每日更新检查策略"
```

### Task 4: Windows 下载、校验和安装器启动

**Files:**
- Create: `test/windows_update_installer_test.dart`
- Create: `lib/features/app_update/application/windows_update_installer.dart`

- [ ] **Step 1: 写失败测试**

用临时目录、假的下载器、假的进程启动器和退出回调测试：下载成功；已有文件经复核后复用；大小不符；SHA-256 不符；失败文件删除；启动成功后退出；启动失败时不退出。

```dart
test('摘要匹配后启动安装器并退出应用', () async {
  final file = await installer.downloadAndVerify(validAsset);
  await installer.launchAndExit(file);
  expect(launchedPath, file.path);
  expect(exitCode, 0);
});

test('摘要不匹配时删除文件且不启动', () async {
  await expectLater(
    installer.downloadAndVerify(assetWithWrongDigest),
    throwsA(isA<UpdatePackageVerificationException>()),
  );
  expect(await downloadedFile.exists(), isFalse);
});
```

- [ ] **Step 2: 运行并观察正确失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/windows_update_installer_test.dart`

Expected: FAIL，原因是安装器运行时不存在。

- [ ] **Step 3: 实现可注入运行时**

```dart
typedef UpdateDownloadProgress = void Function(int received, int total);
typedef UpdateDirectoryProvider = Future<Directory> Function();
typedef UpdateFileDownloader = Future<void> Function(
  Uri source,
  File target,
  UpdateDownloadProgress onProgress,
);
typedef UpdateProcessStarter = Future<void> Function(String path);
typedef UpdateApplicationExit = void Function(int code);

class WindowsUpdateInstaller {
  WindowsUpdateInstaller({
    UpdateDirectoryProvider? directoryProvider,
    UpdateFileDownloader? downloadFile,
    UpdateProcessStarter? startProcess,
    UpdateApplicationExit? exitApplication,
  });
  Future<File> downloadAndVerify(
    AppReleaseAsset asset, {
    UpdateDownloadProgress? onProgress,
  });
  Future<void> launchAndExit(File installer);
}
```

生产默认值使用 `getTemporaryDirectory()`、Dio 流式下载、`Process.start(..., mode: ProcessStartMode.detached)` 和 `exit(0)`。文件名必须先经过 `path.basename`。使用 `sha256.bind(file.openRead()).first` 流式计算摘要；任一异常路径都关闭资源并删除不完整文件。只有进程启动成功后退出应用。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/windows_update_installer_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add -- lib/features/app_update/application/windows_update_installer.dart test/windows_update_installer_test.dart
git commit -m "功能：下载校验并启动更新安装器"
```

### Task 5: 更新弹窗与自动/手动表现流程

**Files:**
- Create: `test/app_update_dialog_test.dart`
- Create: `test/app_update_flow_test.dart`
- Create: `lib/features/app_update/presentation/app_update_dialog.dart`
- Create: `lib/features/app_update/presentation/app_update_flow.dart`

- [ ] **Step 1: 写弹窗失败测试**

验证版本号、发布时间、纯文本 Release body、“稍后提醒”“下载并更新”；下载中显示 `LinearProgressIndicator` 和字节进度、禁止重复触发和遮罩关闭；校验失败显示重试入口。

- [ ] **Step 2: 写流程失败测试**

给 `AppUpdateFlow` 注入 `showRelease`、`showToast`、错误日志回调。验证自动失败静默、自动检查受每日策略限制、手动检查绕过限制、正常检查写日期、手动最新版和测试版提示、发现更新展示弹窗。

```dart
test('自动检查失败保持静默且不写成功日期', () async {
  await flow.runAutomatic();
  expect(toasts, isEmpty);
  expect(policy.isDue, isTrue);
});

test('手动检查本地更高时提示测试版', () async {
  await flow.runManual();
  expect(toasts.single, '当前为高于正式版的测试版本');
});
```

- [ ] **Step 3: 运行并观察正确失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_dialog_test.dart test/app_update_flow_test.dart`

Expected: FAIL，原因是弹窗和流程不存在。

- [ ] **Step 4: 实现弹窗**

`AppUpdateDialog` 使用现有 `GlassDialog`。内部状态仅含 idle/downloading/error、接收字节、总字节和错误文案。Release body 用 `SelectableText` 安全显示。下载期间使用 `PopScope(canPop: false)` 并禁用按钮。下载成功后调用 `launchAndExit`；下载、校验和启动异常分别映射为普通用户可理解的中文文案。

- [ ] **Step 5: 实现共享流程**

```dart
class AppUpdateFlow {
  AppUpdateFlow({
    required AppPlatformCapabilities capabilities,
    required AppUpdateChecker checker,
    required DailyUpdateCheckPolicy policy,
    required Future<void> Function(AppRelease) showRelease,
    required void Function(String) showToast,
    required void Function(Object, StackTrace) logError,
  });
  Future<void> runAutomatic();
  Future<void> runManual();
}
```

非 Windows 直接返回。自动检查仅在 `policy.isDue` 时执行，任何正常结果都 `markSuccessful`，只有可更新才显示 Release；异常只记录。手动检查不读 `isDue`，正常结果写日期并显示对应反馈，异常记录并提示“检查更新失败，请稍后重试”。

- [ ] **Step 6: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_dialog_test.dart test/app_update_flow_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交**

```powershell
git add -- lib/features/app_update/presentation/app_update_dialog.dart lib/features/app_update/presentation/app_update_flow.dart test/app_update_dialog_test.dart test/app_update_flow_test.dart
git commit -m "功能：添加更新弹窗与检查流程"
```

### Task 6: Modular、启动页和关于页接入

**Files:**
- Modify: `lib/app/bindings/infrastructure_bindings.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `lib/pages/about/about_page.dart`
- Modify: `test/init_page_test.dart`
- Modify: `test/about_page_content_test.dart`

- [ ] **Step 1: 写启动顺序失败测试**

```dart
test('先等待本地更新说明关闭再检查远端更新', () async {
  final events = <String>[];
  await runPostNavigationStartupSequence(
    delayUntilPageReady: () async => events.add('delay'),
    showVersionChangelog: () async => events.add('changelog'),
    checkForUpdates: () async => events.add('update'),
  );
  expect(events, const ['delay', 'changelog', 'update']);
});
```

- [ ] **Step 2: 写关于页入口失败测试**

断言“检查更新”位于“当前版本”之后，说明为“从 GitHub 检查最新正式版本”，点击调用 `AppUpdateFlow.runManual()`；原有“更新说明”仍保留且不写 `lastSeenVersion`。

- [ ] **Step 3: 运行并观察正确失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/init_page_test.dart test/about_page_content_test.dart`

Expected: FAIL，原因是后启动序列与手动入口不存在。

- [ ] **Step 4: 注册生产依赖**

在 `registerInfrastructureBindings` 注册 GitHub 客户端、检查器、每日策略、Windows 安装器和共享流程。检查器本地版本使用 `SemanticVersion.parse(AppVersion.current)`；Release 展示使用 `AppDialog.show` 构建 `AppUpdateDialog`；反馈使用 `AppDialog.showToast`；错误使用 `AppLogger().e`。

- [ ] **Step 5: 串行接入启动页**

新增 `runPostNavigationStartupSequence`，按顺序等待页面就绪、等待本地更新说明关闭、执行 `runAutomatic()`。将 `_showVersionChangelog` 改为 `Future<void>` 并等待 `AppDialog.show`。保留现有 500ms 延迟与全部启动行为。

- [ ] **Step 6: 接入关于页**

在“当前版本”和“更新说明”之间新增 `KSettingsTile<void>.navigation`，点击执行 `Modular.get<AppUpdateFlow>().runManual()`。

- [ ] **Step 7: 运行集成回归测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/init_page_test.dart test/about_page_content_test.dart test/shader_startup_resilience_test.dart test/windows_shortcut_repair_test.dart`

Expected: PASS。

- [ ] **Step 8: 提交**

```powershell
git add -- lib/app/bindings/infrastructure_bindings.dart lib/pages/init_page.dart lib/pages/about/about_page.dart test/init_page_test.dart test/about_page_content_test.dart
git commit -m "功能：接入自动与手动更新检查"
```

### Task 7: 同步 2.1.168 测试版契约和用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `tool/windows/installer/看影音测试版.iss`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 先更新版本契约测试并确认失败**

将预期版本改为 `2.1.168`、构建号改为 `20168`。

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart`

Expected: FAIL，指出生产版本仍为 `2.1.167`。

- [ ] **Step 2: 同步版本字段**

- `pubspec.yaml`: `version: 2.1.168+20168`，历史兼容 `msix_version: 2.1.168.0`。
- `lib/core/app_version.dart`: `current = '2.1.168'`。
- Inno Setup 默认 `MyAppVersion "2.1.168"`。

- [ ] **Step 3: 同步普通用户文案**

三个文案来源统一写入：

```text
- Windows 版现在会每天从 GitHub 自动检查一次最新正式版本，也可以在“关于”页面手动检查。
- 发现新版本后，可在应用内查看更新说明、下载安装程序并启动更新。
- 下载完成后会核对安装包大小和 SHA-256，校验失败的文件不会运行。
```

`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 顶部版本改为 2.1.168；`version_history.dart` 顶部加入日期为 `2026-08-23` 的 Windows 2.1.168 条目。不得加入 Android TV 发布文案。

- [ ] **Step 4: 运行版本测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart test/version_consistency_test.dart tool/windows/installer/看影音测试版.iss RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart
git commit -m "发布：更新自动更新测试版至2.1.168"
```

### Task 8: 全量验证与 Windows 测试安装包交付

**Files:**
- Verify: all task files.
- Output: `build/windows/x64/runner/Release/kanyingyin.exe`
- Output: desktop `看影音-2.1.168-测试版-安装程序.exe`

- [ ] **Step 1: 格式化和 diff 检查**

Run: `D:\flutter\bin\dart.bat format lib/features/app_update lib/app/bindings/infrastructure_bindings.dart lib/pages/init_page.dart lib/pages/about/about_page.dart test/app_update_models_test.dart test/github_release_client_test.dart test/app_update_checker_test.dart test/windows_update_installer_test.dart test/app_update_dialog_test.dart test/app_update_flow_test.dart test/init_page_test.dart test/about_page_content_test.dart`

Run: `git diff --check`

Expected: formatter exit 0；diff check 无输出。

- [ ] **Step 2: 运行聚焦更新测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_update_models_test.dart test/github_release_client_test.dart test/app_update_checker_test.dart test/windows_update_installer_test.dart test/app_update_dialog_test.dart test/app_update_flow_test.dart test/init_page_test.dart test/about_page_content_test.dart test/version_consistency_test.dart test/version_history_current_test.dart`

Expected: PASS，0 failures。

- [ ] **Step 3: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub --concurrency=8 --reporter compact`

Expected: PASS，0 failures。

- [ ] **Step 4: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 5: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit 0；Release 主程序 ProductVersion/FileVersion 以 `2.1.168` 开头。

- [ ] **Step 6: 生成并验证 Inno Setup EXE**

Run: `powershell -ExecutionPolicy Bypass -File tool/windows/build_exe_release.ps1`

Expected: exit 0；桌面生成 `看影音-2.1.168-测试版-安装程序.exe`。记录文件大小、SHA-256、ProductVersion 和 Authenticode 状态；未签名必须如实报告。

- [ ] **Step 7: 核对安装边界和 Git 状态**

重新检查 Release 主程序、桌面安装器、卸载注册表和 `Get-AppxPackage -Name com.kanyingyin.player`。除非明确执行安装，本机已安装版应仍为开始前记录的 `2.1.167`，旧 MSIX 仍不存在。检查 `git status --short` 和关键 diff，只提交本轮相关修复。

- [ ] **Step 8: 完成状态**

Expected: 工作树干净；不推送远端、不创建 GitHub tag 或 Release；不构建或交付 Android TV 产物。
