# TrueHD Playback & Full Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Windows 安装包集成可解码 TrueHD/PGS 的完整 libmpv，并建立默认全量记录、10 MB × 10 轮转、远程凭据脱敏和可导出的日志体系。

**Architecture:** 保留 `AppLogger` 作为业务层入口，将文件责任拆到 `LogSanitizer`、`RotatingLogWriter` 和 `DiagnosticLogExporter`。播放器无条件把 libmpv 流写入统一日志，调试开关只控制界面/控制台展示。Windows CMake 固定下载并校验完整 libmpv，排除插件自带精简 DLL 后再安装完整 DLL。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、logger、archive、path_provider、media_kit/libmpv、CMake、MSIX。

---

## File Map

- Create `lib/utils/log_sanitizer.dart`: 远程 URL、请求头和凭据的统一脱敏。
- Create `lib/utils/rotating_log_writer.dart`: UTF-8 串行写入、10 MB × 10 轮转和降级。
- Create `lib/utils/diagnostic_log_exporter.dart`: 日志目录打开、诊断摘要和 ZIP 导出。
- Modify `lib/utils/logger.dart`: 保留现有 API，所有级别默认进入轮转写入器。
- Modify `lib/main.dart`: 捕获 Flutter、平台和 Zone 未处理异常，记录会话启动信息。
- Modify `lib/pages/player/player_controller.dart`: 无条件落盘 libmpv 日志，删除无效 TrueHD 软件视频重试。
- Modify `lib/pages/settings/player_settings.dart`: 将旧调试开关改为日志操作区，增加打开目录和导出按钮。
- Create `windows/cmake/full_libmpv.cmake`: 固定下载、SHA-256 校验和解压完整 libmpv。
- Modify `windows/CMakeLists.txt`: 排除插件精简 DLL，安装完整 DLL。
- Modify `pubspec.yaml`, `RELEASE_NOTES.md`, `lib/utils/version_history.dart`, `lib/request/config/api_endpoints.dart`: 发布版本与用户弹窗文案。
- Create `test/log_sanitizer_test.dart`, `test/rotating_log_writer_test.dart`, `test/diagnostic_log_exporter_test.dart`, `test/windows_full_libmpv_config_test.dart`: 新行为回归测试。
- Modify `test/cloud_playback_resolver_test.dart`, `test/local_video_controller_test.dart`, `test/version_consistency_test.dart`: 播放器与发布契约。

### Task 1: 远程内容脱敏器

**Files:**
- Create: `lib/utils/log_sanitizer.dart`
- Create: `test/log_sanitizer_test.dart`

- [ ] **Step 1: 写入失败测试**

覆盖本地路径保持、远程 URL 收敛为 origin、Authorization/Cookie/API Key/签名替换：

```dart
test('保留本地路径并清理远程凭据', () {
  const sanitizer = LogSanitizer();
  expect(
    sanitizer.sanitize(r'open D:\影片\测试.mkv'),
    contains(r'D:\影片\测试.mkv'),
  );
  final result = sanitizer.sanitize(
    'GET https://user:pass@drive.example.com/private/a.mkv?token=abc '
    'Authorization: Bearer secret Cookie: sid=secret api_key=key',
  );
  expect(result, contains('https://drive.example.com'));
  expect(result, isNot(contains('/private/a.mkv')));
  expect(result, isNot(contains('secret')));
  expect(result, isNot(contains('abc')));
  expect(result, isNot(contains('key')));
  expect(result, contains('[REDACTED]'));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\log_sanitizer_test.dart`

Expected: FAIL，原因是 `LogSanitizer` 尚不存在。

- [ ] **Step 3: 实现最小脱敏器**

实现不可变、无 IO 的 `LogSanitizer.sanitize(String)`：先用 `Uri.tryParse` 处理识别出的远程 URL，再用大小写不敏感表达式覆盖请求头与键值凭据。远程 URL 输出 `${uri.scheme}://${uri.host}${port}`，本地路径不匹配 URL 表达式。

```dart
class LogSanitizer {
  const LogSanitizer();

  String sanitize(String input) {
    var result = input.replaceAllMapped(_remoteUrlPattern, (match) {
      final uri = Uri.tryParse(match.group(0)!);
      if (uri == null || uri.host.isEmpty) return '远程资源';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port';
    });
    for (final pattern in _secretPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    return result;
  }
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\log_sanitizer_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/utils/log_sanitizer.dart test/log_sanitizer_test.dart
git commit -m "新增日志敏感信息脱敏"
```

### Task 2: 日志轮转写入器

**Files:**
- Create: `lib/utils/rotating_log_writer.dart`
- Create: `test/rotating_log_writer_test.dart`

- [ ] **Step 1: 写入失败测试**

使用临时目录和小阈值验证串行写入、轮转、最多 10 个文件、写入失败不向业务层抛出：

```dart
test('达到阈值后轮转且只保留十个文件', () async {
  final writer = RotatingLogWriter(
    directoryProvider: () async => tempDir,
    maxBytes: 64,
    maxFiles: 10,
  );
  for (var i = 0; i < 30; i++) {
    await writer.write('line-$i-${'x' * 32}');
  }
  await writer.flush();
  final files = tempDir.listSync().whereType<File>().toList();
  expect(files.length, lessThanOrEqualTo(10));
  expect(files.any((file) => file.path.endsWith('kanyingyin.log')), isTrue);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\rotating_log_writer_test.dart`

Expected: FAIL，原因是 `RotatingLogWriter` 尚不存在。

- [ ] **Step 3: 实现串行写入和轮转**

构造函数注入目录提供器、阈值和文件数量；默认值为 10 MB、10 个。用 `Future<void> _tail` 串联写入，不让单次异常破坏后续链。活动文件为 `kanyingyin.log`，轮转历史文件名包含 UTC 时间戳与递增序号；轮转后按修改时间删除超额文件。

公开接口：

```dart
class RotatingLogWriter {
  RotatingLogWriter({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = 10 * 1024 * 1024,
    this.maxFiles = 10,
  });

  Future<void> write(String line);
  Future<void> flush();
  Future<Directory?> tryGetDirectory();
  Future<List<File>> listLogFiles();
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\rotating_log_writer_test.dart`

Expected: PASS，且没有未处理异步异常。

- [ ] **Step 5: 提交**

```powershell
git add lib/utils/rotating_log_writer.dart test/rotating_log_writer_test.dart
git commit -m "新增日志轮转写入器"
```

### Task 3: 统一 AppLogger 与未捕获异常

**Files:**
- Modify: `lib/utils/logger.dart`
- Modify: `lib/main.dart`
- Create: `test/logger_pipeline_test.dart`

- [ ] **Step 1: 写入失败测试**

注入内存写入回调，验证 trace/debug/info/warning/error/fatal 全部落盘，ANSI 被移除且消息先脱敏；验证 `forceLog` 不再决定是否写文件。

```dart
test('所有日志等级默认写入文件管线', () async {
  final lines = <String>[];
  final output = AppLogOutput.forTest(lines.add);
  output.output(OutputEvent(Level.info, ['\x1B[32mGET https://x.test/a?t=1\x1B[0m']));
  await output.flush();
  expect(lines.single, contains('GET https://x.test'));
  expect(lines.single, isNot(contains('/a')));
  expect(lines.single, isNot(contains('\x1B')));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\logger_pipeline_test.dart`

Expected: FAIL，因为 info 当前默认不写文件且没有测试注入点。

- [ ] **Step 3: 重构日志输出**

`AppLogOutput` 委托 `RotatingLogWriter`，所有等级写入。输出格式固定为一条头部行加清洗后的正文，使用 UTF-8；保留控制台输出。`getLogsPath` 返回活动文件，`clearLogs` 清空所有轮转文件。

在 `main.dart` 初始化最早阶段注册：

```dart
FlutterError.onError = (details) {
  AppLogger().e(
    'Flutter 未捕获异常',
    error: details.exception,
    stackTrace: details.stack,
  );
};
PlatformDispatcher.instance.onError = (error, stack) {
  AppLogger().f('平台未捕获异常', error: error, stackTrace: stack);
  return true;
};
```

用 `runZonedGuarded` 包裹异步启动，并记录应用版本、系统版本、架构和会话 ID；日志初始化失败仅 `debugPrint`，不阻止启动。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\logger_pipeline_test.dart test\widget_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/utils/logger.dart lib/main.dart test/logger_pipeline_test.dart
git commit -m "统一应用全量日志管线"
```

### Task 4: libmpv 全量日志与 TrueHD 行为

**Files:**
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `test/local_video_controller_test.dart`

- [ ] **Step 1: 写入失败测试**

源码契约测试要求 libmpv 流始终 `forceLog: true`，不再由 `playerDebugMode` 包裹；TrueHD 失败只尝试非 TrueHD 音轨，不调用 `_retryWithSoftwareDecodingForTrueHd`，也不设置 `_forceSoftwareDecodingForCurrentMedia`。

```dart
test('播放器始终记录 mpv 日志且不做无效 TrueHD 视频重建', () {
  final source = File('lib/pages/player/player_controller.dart').readAsStringSync();
  expect(source, contains("AppLogger().i('MPV: \$safeLog', forceLog: true)"));
  expect(source, isNot(contains('_retryWithSoftwareDecodingForTrueHd')));
  expect(source, isNot(contains('_forceAudioCompatibilityForCurrentMedia')));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart`

Expected: FAIL，因为当前只在调试模式记录并存在兼容重建。

- [ ] **Step 3: 修改播放器行为**

无条件把经过 `sanitizePlayerDiagnostic` 的 `mediaPlayer.stream.log` 写入文件；`playerDebugMode` 仅控制 `playerLog` 内存列表或界面展示。保留 `_switchToCompatibleAudioTrackForTrueHd`，删除软件视频解码重建字段、方法和分支。所有 TrueHD 音轨均失败时显示“当前播放器组件无法解码此音轨，请导出诊断日志”，原始 libmpv 错误已在前一步落盘。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/pages/player/player_controller.dart test/local_video_controller_test.dart
git commit -m "记录完整播放器日志并简化 TrueHD 失败处理"
```

### Task 5: 完整 libmpv Windows 构建集成

**Files:**
- Create: `windows/cmake/full_libmpv.cmake`
- Modify: `windows/CMakeLists.txt`
- Create: `test/windows_full_libmpv_config_test.dart`

- [ ] **Step 1: 写入失败测试**

测试读取 CMake 文件，要求固定标准 x64 URL、SHA-256、`EXPECTED_HASH`、排除插件 DLL，并在插件库之后安装完整 DLL：

```dart
test('Windows 构建固定校验并覆盖完整 libmpv', () {
  final config = File('windows/cmake/full_libmpv.cmake').readAsStringSync();
  final root = File('windows/CMakeLists.txt').readAsStringSync();
  expect(config, contains('mpv-dev-x86_64-20260610-git-304426c.7z'));
  expect(config, contains('SHA256=8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9'));
  expect(config, contains('EXPECTED_HASH'));
  expect(root, contains('list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX'));
  expect(root, contains('FULL_LIBMPV_DLL'));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\windows_full_libmpv_config_test.dart`

Expected: FAIL，因为配置文件尚不存在。

- [ ] **Step 3: 实现 CMake 下载与覆盖**

`full_libmpv.cmake` 使用构建目录缓存：

```cmake
set(FULL_LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/full_libmpv/mpv-dev-x86_64-20260610-git-304426c.7z")
set(FULL_LIBMPV_SHA256 "8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9")
file(DOWNLOAD
  "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/mpv-dev-x86_64-20260610-git-304426c.7z"
  "${FULL_LIBMPV_ARCHIVE}"
  EXPECTED_HASH "SHA256=${FULL_LIBMPV_SHA256}"
  TLS_VERIFY ON)
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xzf "${FULL_LIBMPV_ARCHIVE}"
  WORKING_DIRECTORY "${FULL_LIBMPV_DIR}" COMMAND_ERROR_IS_FATAL ANY)
set(FULL_LIBMPV_DLL "${FULL_LIBMPV_DIR}/libmpv-2.dll")
```

项目 CMake 在 `include(flutter/generated_plugins.cmake)` 后包含此文件，并执行：

```cmake
list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX "[/\\\\]libmpv-2\\.dll$")
install(FILES "${FULL_LIBMPV_DLL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
```

确保完整 DLL 的 install 语句位于插件库安装之后，构建失败时不产生精简回退包。

- [ ] **Step 4: 运行配置测试与 Release 构建**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\windows_full_libmpv_config_test.dart
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 测试 PASS，Release 构建成功；`build\windows\x64\runner\Release\libmpv-2.dll` 大小约 117 MB，SHA-256 与解压产物一致。

- [ ] **Step 5: 用真实文件验证解码器**

使用已验证的 libmpv C API 探测脚本打开：

`D:\a TV\僵尸\Rigor.Mortis.2013.1080p.BluRay.Remux.AVC.TrueHD.5.1.2Audio-SONYHD.mkv`

Expected log:

```text
ad Selected decoder: truehd - TrueHD
sub/lavc Using subtitle decoder pgssub
audio=playing, video=playing
```

- [ ] **Step 6: 提交**

```powershell
git add windows/CMakeLists.txt windows/cmake/full_libmpv.cmake test/windows_full_libmpv_config_test.dart
git commit -m "集成完整 Windows libmpv"
```

### Task 6: 日志目录与诊断 ZIP 导出

**Files:**
- Create: `lib/utils/diagnostic_log_exporter.dart`
- Create: `test/diagnostic_log_exporter_test.dart`
- Modify: `pubspec.yaml`

- [ ] **Step 1: 写入失败测试**

使用临时日志文件和注入的摘要提供器，导出 ZIP 后用 `archive` 解包，验证包含 `diagnostic.txt` 与日志、再次脱敏且原文件仍存在。

```dart
test('导出脱敏诊断包且保留原日志', () async {
  final exporter = DiagnosticLogExporter(
    writer: writer,
    summaryProvider: () async => 'version=1.4.7 token=secret',
  );
  final zip = await exporter.exportTo(tempDir);
  final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
  expect(archive.files.map((file) => file.name), contains('diagnostic.txt'));
  expect(String.fromCharCodes(archive.files.first.content), isNot(contains('secret')));
  expect(await original.exists(), isTrue);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\diagnostic_log_exporter_test.dart`

Expected: FAIL，因为导出器尚不存在。

- [ ] **Step 3: 添加 archive 直接依赖并实现导出**

在 `pubspec.yaml` 添加 `archive: ^4.0.9`。`DiagnosticLogExporter` 注入 `RotatingLogWriter`、`LogSanitizer` 和摘要提供器；`openLogDirectory` 在 Windows 使用 `Process.run('explorer.exe', [directory.path])`；导出文件名为 `看影音-诊断日志-YYYYMMDD-HHmmss.zip`。

摘要包含应用版本、Windows 版本、CPU 架构、硬件解码开关、解码器名、日志生成时间和会话 ID，不读取或输出凭据。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\diagnostic_log_exporter_test.dart test\log_sanitizer_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add pubspec.yaml pubspec.lock lib/utils/diagnostic_log_exporter.dart test/diagnostic_log_exporter_test.dart
git commit -m "新增诊断日志导出"
```

### Task 7: 设置页日志入口

**Files:**
- Modify: `lib/pages/settings/player_settings.dart`
- Create: `test/log_settings_ui_test.dart`

- [ ] **Step 1: 写入失败测试**

源码与 Widget 测试要求设置页不再把全量落盘描述为可关闭的“调试模式”，并包含“打开日志目录”“导出诊断日志”和用户可理解的轮转说明。

```dart
test('播放器设置提供日志目录和诊断导出入口', () {
  final source = File('lib/pages/settings/player_settings.dart').readAsStringSync();
  expect(source, contains('打开日志目录'));
  expect(source, contains('导出诊断日志'));
  expect(source, contains('最多保留 10 个日志文件'));
  expect(source, isNot(contains("title: Text('调试模式'")));
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\log_settings_ui_test.dart`

Expected: FAIL，因为入口尚不存在。

- [ ] **Step 3: 实现设置操作**

删除 `playerDebugMode` 开关；保留“日志等级”作为控制台/内存展示级别，但说明文件日志始终完整。添加两个 `SettingsTile.navigation`，按钮使用文件夹与下载/归档图标，调用 `DiagnosticLogExporter.openLogDirectory()` 和 `exportToDownloads()`；成功后 Toast 显示导出完整路径，失败时显示原因但不泄露堆栈。

- [ ] **Step 4: 运行测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\log_settings_ui_test.dart test\local_only_settings_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/pages/settings/player_settings.dart test/log_settings_ui_test.dart
git commit -m "增加日志管理设置入口"
```

### Task 8: 发布文案、全量验证与 MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`

- [ ] **Step 1: 更新版本与用户弹窗文案**

版本升级为 `1.4.7+10407`，MSIX 为 `1.4.7.0`。发布说明与版本历史使用相同含义：

```text
- 现在可以正常播放带 TrueHD 音轨的视频。
- 支持显示和切换蓝光视频内置的 PGS 字幕。
- 应用会自动保存完整运行日志，遇到问题时可以从设置页导出诊断日志。
- 日志会自动清理旧文件，网盘账号、密码和访问凭据不会写入导出内容。
```

- [ ] **Step 2: 运行版本与弹窗测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\log_settings_ui_test.dart`

Expected: PASS，最新 `VersionHistory` 为 1.4.7，更新弹窗读取该条目。

- [ ] **Step 3: 运行全量质量门禁**

Run:

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 所有测试通过、analyze 无问题、Release 构建成功。

- [ ] **Step 4: 实机播放与日志验收**

安装或直接运行 Release，播放问题文件并切换粤语/国语 TrueHD 与简体/繁体 PGS。确认日志包含 `truehd`、`pgssub`、音频输出与播放状态；用设置页导出 ZIP，扫描 ZIP 内容确保不存在 `Authorization`、`Cookie`、`token=`、`api_key=` 或 OpenList 远程路径。

- [ ] **Step 5: 创建、校验并复制 MSIX**

Run:

```powershell
D:\flutter\bin\cache\dart-sdk\bin\dart.exe run msix:create --build-windows false --output-name kanyingyin
```

验证 `AppxManifest.xml` 为 `1.4.7.0`、签名为 `Valid`，计算 SHA-256，并复制到：

`C:\Users\asus\Desktop\看影音-1.4.7.msix`

- [ ] **Step 6: 检查并提交发布改动**

```powershell
git status --short
git diff --check
git add pubspec.yaml lib/request/config/api_endpoints.dart RELEASE_NOTES.md lib/utils/version_history.dart test/version_consistency_test.dart
git commit -m "发布 TrueHD 与全量日志支持"
```

- [ ] **Step 7: 最终完成审计**

确认工作区干净、桌面 MSIX 哈希与构建产物一致、真实文件播放证据完整、日志轮转与脱敏证据完整，然后报告提交列表、测试数量、签名、SHA-256 和安装包路径。
