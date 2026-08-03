# Android 诊断日志分享 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在错误日志页面生成完整脱敏诊断 ZIP，并在 Android 打开系统分享面板，同时交付 Windows 与 Android 2.1.101 测试版安装包。

**Architecture:** 继续由 `DiagnosticLogExporter` 负责刷新、脱敏和归档日志；新增独立的 `DiagnosticLogShareService`，只负责选择临时目录并把 ZIP 交给 `share_plus`。错误日志页面通过可注入回调调用服务，因此正常、空白和读取失败状态都能导出，同时组件测试不会打开真实系统面板。

**Tech Stack:** Flutter 3.41.9、Dart 3.11.5、Material、`archive`、`path_provider`、`share_plus ^11.1.0`、Flutter Test、PowerShell、MSIX、Android APK/AAB。

---

## 文件结构

- Create: `lib/features/logs/application/diagnostic_log_share_service.dart`：临时归档与系统分享边界。
- Create: `test/diagnostic_log_share_service_test.dart`：验证临时目录、ZIP 交接和取消结果。
- Modify: `lib/pages/logs/logs_page.dart`：错误日志页导出入口、忙碌状态和失败提示。
- Modify: `test/logs_page_test.dart`：验证所有页面状态、重复点击、取消和失败反馈。
- Modify: `pubspec.yaml`、`pubspec.lock`：加入与现有 AGP 8.11.1 兼容的 `share_plus ^11.1.0`。
- Generated: `windows/flutter/generated_plugin_registrant.cc`、`windows/flutter/generated_plugins.cmake`：由 Flutter 依赖解析更新，不手工编辑。
- Modify: `pubspec.yaml`、`lib/core/app_version.dart`、`android/app/build.gradle.kts`、`tool/android/build_signed_release.ps1`：同步 Windows 与 Android 2.1.101 测试版本。
- Modify: `lib/utils/version_history.dart`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`README.md`：面向用户说明与当前版本展示。
- Modify: `test/version_consistency_test.dart`、`test/release_config_contract_test.dart`、`test/identity_v2_zero_residue_test.dart`、`test/android_release_packaging_test.dart`、`test/version_history_current_test.dart`：锁定版本和发布文案。

### Task 1: 建立分享服务与依赖边界

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `test/diagnostic_log_share_service_test.dart`
- Create: `lib/features/logs/application/diagnostic_log_share_service.dart`
- Generated: `windows/flutter/generated_plugin_registrant.cc`
- Generated: `windows/flutter/generated_plugins.cmake`

- [ ] **Step 1: 记录交付前状态与已安装 Windows 版本**

Run:

```powershell
chcp 65001
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
git status --short
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, InstallLocation
```

Expected: 工作树除已经提交的设计和计划外无未提交改动；明确记录已安装版本，未安装时记录“未安装”。不得根据 `pubspec.yaml` 代替查询结果。

- [ ] **Step 2: 加入兼容当前 Android 工具链的分享依赖**

在 `pubspec.yaml` 的直接依赖中加入：

```yaml
  share_plus: ^11.1.0
```

使用 11.1.0 是因为它已经提供 `SharePlus.instance.share(ShareParams(...))` 和 `ShareResultStatus.dismissed`，且只要求 AGP 8.3.0；项目现有 AGP 8.11.1 可直接满足。不要升级到要求 AGP 8.12.1 的 12.x/13.x，也不要顺带升级其他依赖。

- [ ] **Step 3: 解析依赖并检查机械生成文件**

Run:

```powershell
D:\flutter\bin\flutter.bat pub get
git status --short
git diff -- pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake
```

Expected: `share_plus 11.1.0` 与 `share_plus_platform_interface 6.1.0` 写入锁文件；Windows 注册文件只新增 `share_plus`，不出现无关依赖升级。

- [ ] **Step 4: 先写分享服务失败测试**

创建 `test/diagnostic_log_share_service_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/logs/application/diagnostic_log_share_service.dart';
import 'package:kanyingyin/utils/diagnostic_log_exporter.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

void main() {
  test('在临时目录生成完整诊断包并交给系统分享', () async {
    final logDirectory =
        await Directory.systemTemp.createTemp('diagnostic-share-logs-');
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('diagnostic-share-output-');
    addTearDown(() async {
      await logDirectory.delete(recursive: true);
      await temporaryDirectory.delete(recursive: true);
    });
    final writer = RotatingLogWriter(
      directoryProvider: () async => logDirectory,
    );
    await writer.write('MPV: [ad] truehd decoder failed token=secret');
    final sharePort = _RecordingDiagnosticLogSharePort(
      DiagnosticLogShareOutcome.dismissed,
    );
    final service = DiagnosticLogShareService(
      exporter: DiagnosticLogExporter(
        writer: writer,
        summaryProvider: () async => 'platform=android token=secret',
      ),
      temporaryDirectoryProvider: () async => temporaryDirectory,
      sharePort: sharePort,
    );

    final outcome = await service.share();

    expect(outcome, DiagnosticLogShareOutcome.dismissed);
    expect(sharePort.files, hasLength(1));
    final zip = sharePort.files.single;
    expect(zip.parent.path, temporaryDirectory.path);
    expect(zip.path, endsWith('.zip'));
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final content = archive.files
        .where((file) => file.isFile)
        .map((file) => utf8.decode(file.content as List<int>))
        .join('\n');
    expect(content, contains('truehd decoder failed'));
    expect(content, isNot(contains('secret')));
    expect(
      await File(
        '${logDirectory.path}${Platform.pathSeparator}'
        '${RotatingLogWriter.activeFileName}',
      ).exists(),
      isTrue,
    );
  });
}

class _RecordingDiagnosticLogSharePort implements DiagnosticLogSharePort {
  _RecordingDiagnosticLogSharePort(this.outcome);

  final DiagnosticLogShareOutcome outcome;
  final List<File> files = <File>[];

  @override
  Future<DiagnosticLogShareOutcome> share(File file) async {
    files.add(file);
    return outcome;
  }
}
```

- [ ] **Step 5: 运行测试并确认按预期失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\diagnostic_log_share_service_test.dart
```

Expected: FAIL，原因是 `diagnostic_log_share_service.dart`、`DiagnosticLogShareService` 或相关类型尚不存在；不能接受语法错误或测试夹具错误。

- [ ] **Step 6: 实现最小分享服务**

创建 `lib/features/logs/application/diagnostic_log_share_service.dart`：

```dart
import 'dart:io';

import 'package:kanyingyin/utils/diagnostic_log_exporter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum DiagnosticLogShareOutcome { shared, dismissed }

typedef DiagnosticTemporaryDirectoryProvider = Future<Directory> Function();

abstract interface class DiagnosticLogSharePort {
  Future<DiagnosticLogShareOutcome> share(File file);
}

class DiagnosticLogShareService {
  DiagnosticLogShareService({
    DiagnosticLogExporter? exporter,
    DiagnosticTemporaryDirectoryProvider? temporaryDirectoryProvider,
    DiagnosticLogSharePort? sharePort,
  })  : _exporter = exporter ?? DiagnosticLogExporter(),
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory,
        _sharePort = sharePort ?? const SharePlusDiagnosticLogSharePort();

  final DiagnosticLogExporter _exporter;
  final DiagnosticTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final DiagnosticLogSharePort _sharePort;

  Future<DiagnosticLogShareOutcome> share() async {
    final directory = await _temporaryDirectoryProvider();
    final file = await _exporter.exportTo(directory);
    return _sharePort.share(file);
  }
}

class SharePlusDiagnosticLogSharePort implements DiagnosticLogSharePort {
  const SharePlusDiagnosticLogSharePort();

  @override
  Future<DiagnosticLogShareOutcome> share(File file) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        title: '分享看影音诊断日志',
        subject: '看影音诊断日志',
        text: '看影音诊断日志（已脱敏）',
        files: <XFile>[
          XFile(file.path, mimeType: 'application/zip'),
        ],
      ),
    );
    return result.status == ShareResultStatus.dismissed
        ? DiagnosticLogShareOutcome.dismissed
        : DiagnosticLogShareOutcome.shared;
  }
}
```

`ShareResultStatus.unavailable` 表示系统已经展示分享能力、但无法判断用户最终动作，不作为失败处理。

- [ ] **Step 7: 运行服务测试并确认通过**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\features\logs\application\diagnostic_log_share_service.dart test\diagnostic_log_share_service_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\diagnostic_log_share_service_test.dart test\diagnostic_log_exporter_test.dart
```

Expected: PASS；ZIP 在注入的临时目录生成、分享端口收到文件、敏感值被移除且原日志仍存在。

- [ ] **Step 8: 提交服务与依赖改动**

Run:

```powershell
git status --short
git diff --check
git add pubspec.yaml pubspec.lock `
  windows/flutter/generated_plugin_registrant.cc `
  windows/flutter/generated_plugins.cmake `
  lib/features/logs/application/diagnostic_log_share_service.dart `
  test/diagnostic_log_share_service_test.dart
git commit -m "功能：增加诊断日志系统分享"
```

Expected: 只提交依赖、生成注册文件、分享服务和对应测试。

### Task 2: 在错误日志页面加入稳定导出入口

**Files:**
- Modify: `test/logs_page_test.dart`
- Modify: `lib/pages/logs/logs_page.dart`

- [ ] **Step 1: 扩展组件测试夹具并写失败测试**

在 `test/logs_page_test.dart` 顶部加入：

```dart
import 'dart:async';

import 'package:kanyingyin/features/logs/application/diagnostic_log_share_service.dart';
```

把 `pumpLogs` 扩展为可注入分享回调：

```dart
Future<void> pumpLogs(
  WidgetTester tester,
  LogArchiveReader reader, {
  double width = 900,
  Future<DiagnosticLogShareOutcome> Function()? shareDiagnosticLogs,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: LogsPage(
        reader: reader,
        shareDiagnosticLogs: shareDiagnosticLogs,
      ),
    ),
  );
  for (var frame = 0; frame < 50; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
}
```

追加以下测试：

```dart
testWidgets('正常、空白和读取失败状态都能导出诊断日志', (tester) async {
  for (final reader in <LogArchiveReader>[
    await readerWith('[2026-08-03T04:15:42.075] WARNING\nTrueHD 解码失败'),
    await readerWith(''),
    _ThrowingLogArchiveReader(),
  ]) {
    await pumpLogs(
      tester,
      reader,
      shareDiagnosticLogs: () async => DiagnosticLogShareOutcome.dismissed,
    );
    expect(find.byTooltip('导出诊断日志'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }
});

testWidgets('导出期间禁用按钮并阻止重复分享', (tester) async {
  final completer = Completer<DiagnosticLogShareOutcome>();
  var calls = 0;
  await pumpLogs(
    tester,
    await readerWith('[2026-08-03T04:15:42.075] ERROR\n播放器失败'),
    shareDiagnosticLogs: () {
      calls += 1;
      return completer.future;
    },
  );

  await tester.tap(find.byTooltip('导出诊断日志'));
  await tester.pump();

  expect(calls, 1);
  final button = tester.widget<IconButton>(
    find.byKey(const ValueKey('export-diagnostic-logs')),
  );
  expect(button.onPressed, isNull);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  completer.complete(DiagnosticLogShareOutcome.dismissed);
  await tester.pumpAndSettle();
  expect(calls, 1);
  expect(find.text('导出诊断日志失败，请稍后重试'), findsNothing);
});

testWidgets('导出异常显示明确提示', (tester) async {
  await pumpLogs(
    tester,
    await readerWith(''),
    shareDiagnosticLogs: () async => throw StateError('fixture'),
  );

  await tester.tap(find.byTooltip('导出诊断日志'));
  await tester.pump();

  expect(find.text('导出诊断日志失败，请稍后重试'), findsOneWidget);
});
```

- [ ] **Step 2: 运行组件测试并确认按预期失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\logs_page_test.dart
```

Expected: FAIL，原因是 `LogsPage` 尚不接受 `shareDiagnosticLogs`，且页面不存在“导出诊断日志”按钮。

- [ ] **Step 3: 实现页面注入、忙碌状态和错误处理**

在 `lib/pages/logs/logs_page.dart` 引入分享服务：

```dart
import 'package:kanyingyin/features/logs/application/diagnostic_log_share_service.dart';
```

扩展组件构造器：

```dart
class LogsPage extends StatefulWidget {
  const LogsPage({
    super.key,
    this.reader,
    this.shareDiagnosticLogs,
  });

  final LogArchiveReader? reader;
  final Future<DiagnosticLogShareOutcome> Function()? shareDiagnosticLogs;

  @override
  State<LogsPage> createState() => _LogsPageState();
}
```

在状态类加入：

```dart
late final Future<DiagnosticLogShareOutcome> Function() _shareDiagnosticLogs;
bool _isExporting = false;
```

在 `initState` 中初始化：

```dart
_shareDiagnosticLogs =
    widget.shareDiagnosticLogs ?? DiagnosticLogShareService().share;
```

新增导出方法：

```dart
Future<void> _exportDiagnosticLogs() async {
  if (_isExporting) return;
  setState(() => _isExporting = true);
  try {
    await _shareDiagnosticLogs();
  } on Object {
    if (mounted) {
      AppDialog.showToast(message: '导出诊断日志失败，请稍后重试');
    }
  } finally {
    if (mounted) setState(() => _isExporting = false);
  }
}
```

把 `Scaffold.appBar` 改为始终存在的稳定图标入口：

```dart
appBar: SysAppBar(
  title: const Text('运行记录'),
  actions: [
    Tooltip(
      message: '导出诊断日志',
      child: IconButton(
        key: const ValueKey('export-diagnostic-logs'),
        onPressed: _isExporting
            ? null
            : () => unawaited(_exportDiagnosticLogs()),
        icon: _isExporting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.share_outlined),
      ),
    ),
  ],
),
```

不要把按钮放进 `_buildContent`，否则空白和读取失败状态无法导出。不要改变复制、搜索、筛选、清空、动画时长或列表层级。

- [ ] **Step 4: 运行组件与日志回归测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\pages\logs\logs_page.dart test\logs_page_test.dart
D:\flutter\bin\flutter.bat test --no-pub `
  test\logs_page_test.dart `
  test\log_presentation_components_test.dart `
  test\diagnostic_log_share_service_test.dart `
  test\diagnostic_log_exporter_test.dart `
  test\log_sanitizer_test.dart `
  test\logger_pipeline_test.dart
```

Expected: PASS；所有状态存在入口、重复点击只调用一次、取消无错误提示、真实异常有明确提示。

- [ ] **Step 5: 检查 Android 插件注册并提交页面改动**

Run:

```powershell
Select-String -Path .flutter-plugins-dependencies -Pattern 'share_plus'
git status --short
git diff --check
git diff -- lib/pages/logs/logs_page.dart test/logs_page_test.dart
git add lib/pages/logs/logs_page.dart test/logs_page_test.dart
git commit -m "功能：在错误日志页分享诊断包"
```

Expected: Android 插件清单包含 `share_plus`；提交只包含错误日志页和组件测试。

### Task 3: 同步测试版本与用户文案

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/android_release_packaging_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`

- [ ] **Step 1: 先把发布契约测试改为目标版本**

在发布测试中统一使用：

```dart
const expectedVersion = '2.1.101';
const expectedBuildNumber = '20101';
const expectedAndroidVersion = '2.1.101';
const expectedAndroidVersionCode = '20101';
```

具体修改：

```text
test/version_consistency_test.dart:
  测试名改为“二点一零一测试版双平台版本和发布文案保持一致”
  当前文案关键词改为：诊断日志、系统分享、脱敏、Windows、Android、不会修改或删除

test/release_config_contract_test.dart:
  1.0.4+10004 -> 2.1.101+20101
  1.0.4.0 -> 2.1.101.0
  当前 Android 版本 1.0.1 -> 2.1.101

test/identity_v2_zero_residue_test.dart:
  currentVersion 1.0.4 -> 2.1.101
  buildNumber 10004 -> 20101

test/android_release_packaging_test.dart:
  androidVersionName 1.0.1 -> 2.1.101
  androidVersionCode 10001 -> 20101

test/version_history_current_test.dart:
  Windows 当前版本查询 1.0.4 -> 2.1.101
  Android 平台映射期望 2.1.101
  关键词包含“诊断日志”“系统分享”“脱敏”“不会修改或删除”
  Android 文案不得包含 Windows
```

- [ ] **Step 2: 运行发布契约测试并确认按预期失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test\version_consistency_test.dart `
  test\release_config_contract_test.dart `
  test\identity_v2_zero_residue_test.dart `
  test\android_release_packaging_test.dart `
  test\version_history_current_test.dart
```

Expected: FAIL，明确显示当前源码仍为 Windows 1.0.4 / Android 1.0.1，且缺少本轮用户文案。

- [ ] **Step 3: 同步所有版本源**

应用以下精确版本：

```yaml
# pubspec.yaml
version: 2.1.101+20101

msix_config:
  msix_version: 2.1.101.0
```

```dart
// lib/core/app_version.dart
static const String current = '2.1.101';
```

```kotlin
// android/app/build.gradle.kts
val androidVersionName = "2.1.101"
val androidVersionCode = 20101
```

```powershell
# tool/android/build_signed_release.ps1
$androidVersion = '2.1.101'
$androidVersionCode = 20101

if ($windowsVersion -ne '2.1.101' -or $windowsBuildNumber -ne '20101') {
    throw "Windows pubspec 版本必须为 2.1.101+20101，实际为 $windowsVersion+$windowsBuildNumber"
}
```

- [ ] **Step 4: 增加当前版本历史与 Android 映射**

在 `lib/utils/version_history.dart` 顶部 Android 版本区域加入：

```dart
const VersionHistory _androidDiagnosticLogSharePrerelease = VersionHistory(
  version: '2.1.101',
  date: '2026-08-03',
  isPrerelease: true,
  changes: [
    'Android 2.1.101 测试版在错误日志页面新增“导出诊断日志”入口，遇到播放问题时可直接生成完整诊断包',
    'Android 导出后会打开系统分享面板，可发送到其他应用或保存到文件，无需申请全盘存储权限',
    '诊断包包含应用、系统、解码设置和播放器底层日志，并继续隐藏网盘凭据、Token、请求头与远程媒体完整地址',
    '导出不会清空原日志；日志为空或页面读取失败时仍可尝试取得底层诊断文件',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);
```

在 `versionHistoryList` 首位加入 2.1.101 测试版：

```dart
VersionHistory(
  version: '2.1.101',
  date: '2026-08-03',
  isPrerelease: true,
  changes: [
    '本轮同步提供 Windows 与 Android 2.1.101 测试版，分别使用 MSIX、APK 和 AAB 交付',
    '错误日志页面新增诊断包导出入口，Android 可直接通过系统分享面板发送或保存完整脱敏日志',
    '诊断包继续包含应用、系统、解码设置和播放器底层日志，便于定位 TrueHD 等播放兼容问题',
    '网盘凭据、Token、请求头和远程媒体完整地址不会进入导出内容，导出也不会清空原日志',
    'Windows 原有下载目录导出行为保持不变，播放器、媒体库和网盘文件处理逻辑不变',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
),
```

在 `versionHistoryForCurrent` 的 Android 映射首位加入：

```dart
if (currentVersion == '2.1.101' && platform == AppPlatformKind.android) {
  return const <VersionHistory>[_androidDiagnosticLogSharePrerelease];
}
```

保留 1.0.4/1.0.1 及更早历史，不能覆盖旧条目。

- [ ] **Step 5: 更新发布说明、弹窗和 README**

在 `RELEASE_NOTES.md` 顶部新增 `2.1.101+20101` 区块，明确：

```markdown
## 2.1.101+20101

MSIX 版本：2.1.101.0

APK/AAB 版本：2.1.101 (20101)

### Windows 测试版更新内容

标题：看影音 2.1.101 测试版

- 本轮同步提供 Windows 与 Android 2.1.101 测试版，分别使用 MSIX、APK 和 AAB 交付。
- 错误日志页面新增诊断包导出入口，Android 可直接通过系统分享面板发送或保存完整脱敏日志。
- 诊断包继续包含应用、系统、解码设置和播放器底层日志，便于定位 TrueHD 等播放兼容问题。
- 网盘凭据、Token、请求头和远程媒体完整地址不会进入导出内容，导出也不会清空原日志。
- Windows 原有下载目录导出行为保持不变，播放器、媒体库和网盘文件处理逻辑不变。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

### Android 测试版更新内容

标题：看影音 Android 2.1.101 测试版

- Android 2.1.101 测试版在错误日志页面新增“导出诊断日志”入口，遇到播放问题时可直接生成完整诊断包。
- 导出后会打开系统分享面板，可发送到其他应用或保存到文件，无需申请全盘存储权限。
- 诊断包包含应用、系统、解码设置和播放器底层日志，并继续隐藏网盘凭据、Token、请求头与远程媒体完整地址。
- 导出不会清空原日志；日志为空或页面读取失败时仍可尝试取得底层诊断文件。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。
```

把 `UPDATE_DIALOG_COPY.md` 当前版本整体同步为同一组测试版本和文案。把 `README.md` 的当前版本更新为 Windows / Android 2.1.101，并保留 OpenList 调试提示与安装格式说明。

- [ ] **Step 6: 运行发布契约测试并确认通过**

Run:

```powershell
D:\flutter\bin\dart.bat format `
  lib\core\app_version.dart `
  lib\utils\version_history.dart `
  test\version_consistency_test.dart `
  test\release_config_contract_test.dart `
  test\identity_v2_zero_residue_test.dart `
  test\android_release_packaging_test.dart `
  test\version_history_current_test.dart
D:\flutter\bin\flutter.bat test --no-pub `
  test\version_consistency_test.dart `
  test\release_config_contract_test.dart `
  test\identity_v2_zero_residue_test.dart `
  test\android_release_packaging_test.dart `
  test\version_history_current_test.dart
```

Expected: PASS；所有版本源、Android 脚本和用户文案一致。

- [ ] **Step 7: 检查关键差异但暂不提交**

Run:

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml lib/core/app_version.dart `
  android/app/build.gradle.kts tool/android/build_signed_release.ps1 `
  lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md
```

Expected: 仅出现双平台 2.1.101 测试版与本轮日志分享文案；旧版本历史仍保留。版本改动等待完整构建验证后一起提交。

### Task 4: 完整质量门禁与双平台交付

**Files:**
- Verify: all tracked changes
- Output: `C:\Users\asus\Desktop\看影音-2.1.101.msix`
- Output: `C:\Users\asus\Desktop\看影音-2.1.101.apk`
- Output: `C:\Users\asus\Desktop\看影音-2.1.101.aab`

- [ ] **Step 1: 运行完整测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub
```

Expected: PASS，0 个失败。不得用之前的针对性测试代替。

- [ ] **Step 2: 运行完整静态分析**

Run:

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: `No issues found!`，无 error。

- [ ] **Step 3: 构建 Windows Release 并生成签名 MSIX**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: Windows Release 构建、MSIX 生成、签名及清单验证全部通过，桌面生成 `看影音-2.1.101.msix`。脚本不得安装包。

- [ ] **Step 4: 独立核验 Windows 包版本、签名和哈希**

Run:

```powershell
$msix = Join-Path ([Environment]::GetFolderPath('Desktop')) '看影音-2.1.101.msix'
Get-Item -LiteralPath $msix | Select-Object FullName, Length, LastWriteTime
Get-AuthenticodeSignature -LiteralPath $msix |
  Select-Object Status, StatusMessage, SignerCertificate
Get-FileHash -Algorithm SHA256 -LiteralPath $msix
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, InstallLocation
```

Expected: 文件存在、签名状态有效、清单版本为 2.1.101.0。未执行安装，因此已安装版本应与 Task 1 记录的 2.1.100.0 一致，并明确记录新测试包尚未安装。

- [ ] **Step 5: 构建、签名并验证 Android APK/AAB**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tool\android\build_signed_release.ps1
```

Expected: Release APK 和 AAB 构建通过；APK v2 签名有效，AAB `jarsigner -verify -strict` 有效；桌面生成 `看影音-2.1.101.apk` 与 `看影音-2.1.101.aab`。

- [ ] **Step 6: 独立核验 Android 包身份、版本和桌面副本**

Run:

```powershell
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$apk = 'build\app\outputs\flutter-apk\app-release.apk'
$aab = 'build\app\outputs\bundle\release\app-release.aab'
& $aapt dump badging $apk | Select-String '^package:'
& $apksigner verify --verbose --print-certs $apk
Get-FileHash -Algorithm SHA256 $apk, $aab,
  (Join-Path ([Environment]::GetFolderPath('Desktop')) '看影音-2.1.101.apk'),
  (Join-Path ([Environment]::GetFolderPath('Desktop')) '看影音-2.1.101.aab')
```

Expected: `com.kanyingyin.player`、versionName `2.1.101`、versionCode `20101`；构建目录和桌面对应文件的 SHA256 分别一致。

- [ ] **Step 7: 记录实机限制**

Run:

```powershell
$adb = Get-Command adb -ErrorAction SilentlyContinue
if ($adb) { & $adb.Source devices -l }
```

Expected: 只读取设备状态，不自动安装 APK。没有已连接设备时，明确记录“系统分享面板仍需 Android 实机验收”，不得声称实机已验证；不要启动本机 Android 模拟器。

- [ ] **Step 8: 最终检查并提交版本交付改动**

Run:

```powershell
git status --short
git diff --check
git diff --stat
git diff -- pubspec.yaml lib/core/app_version.dart `
  android/app/build.gradle.kts tool/android/build_signed_release.ps1 `
  lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md `
  test/version_consistency_test.dart test/release_config_contract_test.dart `
  test/identity_v2_zero_residue_test.dart test/android_release_packaging_test.dart `
  test/version_history_current_test.dart
git add pubspec.yaml lib/core/app_version.dart `
  android/app/build.gradle.kts tool/android/build_signed_release.ps1 `
  lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md `
  test/version_consistency_test.dart test/release_config_contract_test.dart `
  test/identity_v2_zero_residue_test.dart test/android_release_packaging_test.dart `
  test/version_history_current_test.dart
git commit -m "发布：交付2.1.101测试版"
git status --short
git log -4 --oneline --decorate
```

Expected: 只提交本轮版本、文案和发布测试；最终工作树干净。不得提交密钥、证书、构建目录或桌面产物。

## 完成标准

- 错误日志页面在正常、空白、读取失败状态都能导出。
- Android 系统分享使用完整脱敏 ZIP，取消不报错，失败有明确提示。
- 原日志不被删除，筛选条件不影响导出内容。
- `share_plus` 固定在兼容 AGP 8.11.1 的 11.x，不升级其他依赖。
- 完整测试、静态分析、Windows Release/MSIX 和 Android Release APK/AAB 全部通过。
- Windows 2.1.101 MSIX 与 Android 2.1.101 APK/AAB 位于桌面并完成版本、签名和哈希核验。
- 未连接 Android 实机时，不宣称系统分享面板已实机验证。
