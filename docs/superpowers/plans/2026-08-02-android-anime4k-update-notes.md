# Android Anime4K 与更新说明入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Android Anime4K 把多条着色器路径误当成一个文件名的问题，在关于页当前版本下方增加只查看本版本说明的入口，并交付 Windows/Android 2.1.98。

**Architecture:** `Anime4kShaderExecutor` 不再自行拼接 mpv 路径列表，而是先清空、再逐条追加并在失败时回滚。更新日志弹窗抽到独立展示文件，启动页继续管理已读状态，关于页只读取当前平台的当前版本历史并手动展示。版本元数据、普通用户文案和双平台签名产物统一升级到 2.1.98。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Flutter Modular、Material、flutter_test、media_kit/mpv、PowerShell、Gradle、MSIX。

---

### Task 1: 用逐条追加修复 Anime4K 着色器列表

**Files:**
- Modify: `test/anime4k_shader_executor_test.dart`
- Modify: `lib/features/player/application/anime4k_shader_executor.dart`

- [ ] **Step 1: 把旧 set 测试改为 Android 路径的清空与逐条追加测试**

```dart
test('Android 路径先清空并按顺序逐条追加', () async {
  final commands = <List<String>>[];
  final executor = Anime4kShaderExecutor(
    command: (command) async => commands.add(command),
  );

  await executor.apply(
    Anime4kAction.enableEfficiency,
    shaderPaths: const <String>[
      '/data/user/0/com.kanyingyin.player/files/anime_shaders/a.glsl',
      '/data/user/0/com.kanyingyin.player/files/anime_shaders/b.glsl',
    ],
  );

  expect(commands, <List<String>>[
    <String>['change-list', 'glsl-shaders', 'clr', ''],
    <String>[
      'change-list',
      'glsl-shaders',
      'append',
      '/data/user/0/com.kanyingyin.player/files/anime_shaders/a.glsl',
    ],
    <String>[
      'change-list',
      'glsl-shaders',
      'append',
      '/data/user/0/com.kanyingyin.player/files/anime_shaders/b.glsl',
    ],
  ]);
});
```

- [ ] **Step 2: 增加 Windows 盘符保持完整的回归测试**

```dart
test('Windows 盘符路径逐条追加且不会按冒号拆分', () async {
  final commands = <List<String>>[];
  final executor = Anime4kShaderExecutor(
    command: (command) async => commands.add(command),
  );

  await executor.apply(
    Anime4kAction.enableQuality,
    shaderPaths: const <String>[r'C:\anime shaders\quality.glsl'],
  );

  expect(commands.last, <String>[
    'change-list',
    'glsl-shaders',
    'append',
    r'C:\anime shaders\quality.glsl',
  ]);
});
```

- [ ] **Step 3: 把失败测试收紧为第二次追加失败后清空且重抛首次错误**

```dart
test('第二个着色器追加失败后清空并重新抛出首次错误', () async {
  final commands = <List<String>>[];
  final error = StateError('shader failed');
  final executor = Anime4kShaderExecutor(command: (command) async {
    commands.add(command);
    if (command[2] == 'append' && command[3] == 'b.glsl') throw error;
  });

  await expectLater(
    executor.apply(
      Anime4kAction.enableQuality,
      shaderPaths: const <String>['a.glsl', 'b.glsl'],
    ),
    throwsA(same(error)),
  );
  expect(commands, <List<String>>[
    <String>['change-list', 'glsl-shaders', 'clr', ''],
    <String>['change-list', 'glsl-shaders', 'append', 'a.glsl'],
    <String>['change-list', 'glsl-shaders', 'append', 'b.glsl'],
    <String>['change-list', 'glsl-shaders', 'clr', ''],
  ]);
});
```

- [ ] **Step 4: 运行定向测试并确认旧实现按预期失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/anime4k_shader_executor_test.dart`

Expected: FAIL；旧实现只发出一条 `set` 命令，无法满足清空与逐条 `append` 的期望。

- [ ] **Step 5: 写入最小实现**

```dart
try {
  await _clear();
  for (final shaderPath in shaderPaths) {
    await _command(<String>[
      'change-list',
      'glsl-shaders',
      'append',
      shaderPath,
    ]);
  }
} on Object catch (error, stackTrace) {
  try {
    await _clear();
  } on Object {
    // 清空失败不能覆盖首次着色器错误。
  }
  Error.throwWithStackTrace(error, stackTrace);
}
```

- [ ] **Step 6: 运行定向测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/anime4k_shader_executor_test.dart`

Expected: PASS；官方效率档、质量档、Android/Windows 路径、失败回滚和关闭命令全部通过。

- [ ] **Step 7: 提交 Anime4K 修复**

```powershell
git add test/anime4k_shader_executor_test.dart lib/features/player/application/anime4k_shader_executor.dart
git commit -m "修复：兼容安卓Anime4K着色器列表"
```

### Task 2: 抽取更新日志弹窗并在关于页增加入口

**Files:**
- Create: `lib/features/version/presentation/version_changelog_dialog.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `lib/pages/about/about_page.dart`
- Modify: `test/about_page_content_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 增加关于页入口源码契约测试**

```dart
test('当前版本下方提供当前平台更新说明入口', () {
  final source = File('lib/pages/about/about_page.dart').readAsStringSync();
  final currentVersionIndex = source.indexOf("'当前版本'");
  final updateNotesIndex = source.indexOf("'更新说明'");

  expect(updateNotesIndex, greaterThan(currentVersionIndex));
  expect(source, contains("'查看当前版本的更新内容'"));
  expect(source, contains('versionHistoryForCurrent('));
  expect(source, contains('AppVersion.current'));
  expect(source, contains('detectAppPlatform().kind'));
  expect(source, contains('VersionChangelogDialog(versions: versions)'));
  expect(source, contains("'当前版本暂无更新说明'"));
  expect(source, isNot(contains('SettingBoxKey.lastSeenVersion')));
});
```

- [ ] **Step 2: 更新组件测试导入路径并运行 RED**

把 `test/version_history_current_test.dart` 中的 `init_page.dart` 导入替换为：

```dart
import 'package:kanyingyin/features/version/presentation/version_changelog_dialog.dart';
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test/about_page_content_test.dart test/version_history_current_test.dart`

Expected: FAIL；共享展示文件和关于页入口尚不存在。

- [ ] **Step 3: 创建共享更新日志弹窗文件**

创建 `lib/features/version/presentation/version_changelog_dialog.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/utils/version_history.dart';

class VersionChangelogDialog extends StatelessWidget {
  const VersionChangelogDialog({super.key, required this.versions});

  final List<VersionHistory> versions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('版本更新日志'),
      content: VersionChangelogContent(versions: versions),
      actions: [
        TextButton(
          onPressed: () => AppDialog.dismiss<void>(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class VersionChangelogContent extends StatelessWidget {
  const VersionChangelogContent({super.key, required this.versions});

  final List<VersionHistory> versions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final version in versions) ...[
            Text(
              'v${version.version}  ${version.releaseLabel}  ${version.date}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final change in version.changes)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text(
                  '- $change',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 让启动页复用共享组件**

在 `lib/pages/init_page.dart` 增加：

```dart
import 'package:kanyingyin/features/version/presentation/version_changelog_dialog.dart';
```

删除原文件从 `class VersionChangelogDialog` 到 `VersionChangelogContent` 结束的定义；`_showVersionChangelog()` 的 `lastSeenVersion` 判断、写入时机和弹窗调用保持不变。

- [ ] **Step 5: 在关于页实现手动查看入口**

新增导入：

```dart
import 'package:kanyingyin/features/version/presentation/version_changelog_dialog.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/version_history.dart';
```

新增方法：

```dart
void _showCurrentVersionChangelog() {
  final versions = versionHistoryForCurrent(
    AppVersion.current,
    platform: detectAppPlatform().kind,
  );
  if (versions.isEmpty) {
    AppDialog.showToast(message: '当前版本暂无更新说明');
    return;
  }
  AppDialog.show<void>(
    builder: (context) => VersionChangelogDialog(versions: versions),
  );
}
```

在“当前版本”条目正下方、同一个 `KSettingsSection` 中增加：

```dart
KSettingsTile<void>.navigation(
  onPressed: (_) => _showCurrentVersionChangelog(),
  title: Text('更新说明', style: TextStyle(fontFamily: fontFamily)),
  description: Text(
    '查看当前版本的更新内容',
    style: TextStyle(fontFamily: fontFamily),
  ),
),
```

- [ ] **Step 6: 运行定向测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/about_page_content_test.dart test/version_history_current_test.dart test/shader_startup_resilience_test.dart`

Expected: PASS；入口顺序、平台参数、空数据提示、共享弹窗渲染和启动流程均无回归。

- [ ] **Step 7: 提交更新说明入口**

```powershell
git add lib/features/version/presentation/version_changelog_dialog.dart lib/pages/init_page.dart lib/pages/about/about_page.dart test/about_page_content_test.dart test/version_history_current_test.dart
git commit -m "功能：在关于页增加更新说明入口"
```

### Task 3: 同步 2.1.98 版本与普通用户文案

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/android_release_packaging_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 先把版本契约测试期望改为 2.1.98**

统一测试期望：

```dart
const expectedVersion = '2.1.98';
const expectedBuildNumber = '20198';
```

同时把 Android 打包、身份和发布配置测试中的 `2.1.97`/`20197` 更新为 `2.1.98`/`20198`，并在版本历史测试中新增 Windows 双平台说明与 Android 专属说明断言。当前文案至少覆盖：`Android`、`Anime4K`、`逐个`、`更新说明`、`普通播放`、`不会修改或删除`；Android 专属说明不得包含 `Windows`。

- [ ] **Step 2: 运行版本定向测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/android_release_packaging_test.dart test/identity_v2_zero_residue_test.dart test/release_config_contract_test.dart`

Expected: FAIL；生产配置仍为 2.1.97，且版本历史中没有 2.1.98。

- [ ] **Step 3: 更新所有版本元数据**

执行以下精确替换：

```text
pubspec.yaml: version: 2.1.97+20197 -> version: 2.1.98+20198
pubspec.yaml: msix_version: 2.1.97.0 -> msix_version: 2.1.98.0
lib/core/app_version.dart: current = '2.1.97' -> current = '2.1.98'
android/app/build.gradle.kts: androidVersionName = "2.1.97" -> "2.1.98"
android/app/build.gradle.kts: androidVersionCode = 20197 -> 20198
tool/android/build_signed_release.ps1: $androidVersion = '2.1.97' -> '2.1.98'
tool/android/build_signed_release.ps1: $androidVersionCode = 20197 -> 20198
tool/android/build_signed_release.ps1: Windows pubspec 版本必须为 2.1.97+20197 -> 2.1.98+20198
```

- [ ] **Step 4: 增加 2.1.98 双平台和 Android 专属版本历史**

在 Android 专属常量区增加：

```dart
const VersionHistory _androidAnime4kShaderListRelease = VersionHistory(
  version: '2.1.98',
  date: '2026-08-02',
  isPrerelease: true,
  changes: [
    '修复 Android 启用 Anime4K 时可能把多条着色器路径误当成一个文件名、导致视频无法打开的问题',
    'Anime4K 着色器现在按既定顺序逐个加载；任一着色器失败后会安全清空增强并保留普通播放',
    '关于页当前版本下方新增“更新说明”，可随时查看本版本 Android 更新内容，不影响升级后的首次启动提示',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);
```

在 `versionHistoryList` 顶部增加：

```dart
VersionHistory(
  version: '2.1.98',
  date: '2026-08-02',
  isPrerelease: true,
  changes: [
    '本轮同步提供 Windows 与 Android 2.1.98 测试版，分别使用 MSIX、APK 和 AAB 交付',
    '修复 Android 启用 Anime4K 时可能把多条着色器路径误当成一个文件名、导致视频无法打开的问题',
    'Anime4K 着色器现在按既定顺序逐个加载；任一着色器失败后会安全清空增强并保留普通播放',
    '关于页当前版本下方新增“更新说明”，可随时查看本版本内容且不会改写首次启动更新提示状态',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
),
```

在 `versionHistoryForCurrent()` 最前面增加：

```dart
if (currentVersion == '2.1.98' && platform == AppPlatformKind.android) {
  return const <VersionHistory>[_androidAnime4kShaderListRelease];
}
```

- [ ] **Step 5: 更新 README、RELEASE_NOTES 和 UPDATE_DIALOG_COPY**

README 的当前版本、Android 版本和本轮构建段落从 `2.1.97` 精确替换为 `2.1.98`。

在 `RELEASE_NOTES.md` 标题后增加：

```markdown
## 2.1.98+20198

MSIX 版本：2.1.98.0

APK/AAB 版本：2.1.98 (20198)

### 更新弹窗文案

标题：看影音 2.1.98 测试版

- 本轮同步提供 Windows 与 Android 2.1.98 测试版，分别使用 MSIX、APK 和 AAB 交付。
- 修复 Android 启用 Anime4K 时可能把多条着色器路径误当成一个文件名、导致视频无法打开的问题。
- Anime4K 着色器现在按既定顺序逐个加载；任一着色器失败后会安全清空增强并保留普通播放。
- 关于页当前版本下方新增“更新说明”，可随时查看本版本内容且不会改写首次启动更新提示状态。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。
```

把 `UPDATE_DIALOG_COPY.md` 当前版本段落更新为 2.1.98/20198，并让 Windows 正文使用上述五条说明；Android 正文使用 `_androidAnime4kShaderListRelease` 的四条说明，标题为“看影音 Android 2.1.98 测试版”。

- [ ] **Step 6: 运行版本定向测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/android_release_packaging_test.dart test/identity_v2_zero_residue_test.dart test/release_config_contract_test.dart`

Expected: PASS；版本号、安装包号、双平台文案、Android 专属文案和打包脚本一致。

- [ ] **Step 7: 提交 2.1.98 发布配置**

```powershell
git add pubspec.yaml lib/core/app_version.dart android/app/build.gradle.kts tool/android/build_signed_release.ps1 README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/android_release_packaging_test.dart test/identity_v2_zero_residue_test.dart test/release_config_contract_test.dart
git commit -m "发布：更新2.1.98双平台版本说明"
```

### Task 4: 完整验证、签名打包、桌面交付和本地合并

**Files:**
- Verify only: tracked source and generated release artifacts

- [ ] **Step 1: 检查改动范围和锁文件**

Run: `git status --short`

Run: `git diff main...HEAD --check`

Run: `git diff main...HEAD -- pubspec.lock`

Expected: 只有本计划涉及的源码、测试、文档和版本文件；`pubspec.lock` 无改动；无空白错误。

- [ ] **Step 2: 运行完整测试与静态分析**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: PASS，0 failures。

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 3: 构建并验证 Android 签名 APK/AAB**

若新 worktree 无 Android 原生缓存，复制已验证的 `D:\KanYingYin\build\media_kit_libs_android_video\v1.2.5` 到当前 worktree 对应生成目录；随后运行：

Run: `powershell -ExecutionPolicy Bypass -File tool\android\build_signed_release.ps1`

Expected: APK/AAB Release 构建成功，`apksigner` 与 `jarsigner` 验证成功，应用标识为 `com.kanyingyin.player`，版本为 `2.1.98 (20198)`，桌面生成 `看影音-2.1.98.apk` 与 `看影音-2.1.98.aab`。

- [ ] **Step 4: 构建并验证 Windows 签名 MSIX 与异机包**

如 NuGet 未在 PATH 中，临时把 `D:\KanYingYin\build\tools` 加入当前构建进程 PATH；如插件需要，可复用 `D:\KanYingYin\build\windows\x64\packages`。运行：

Run: `powershell -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1`

Expected: Windows Release 构建成功，签名验证为 `Valid`，MSIX 清单 Identity 为 `com.kanyingyin.player`、Version 为 `2.1.98.0`、Architecture 为 `x64`；桌面生成 `看影音-2.1.98.msix` 与 `看影音-2.1.98-异机安装包.zip`，ZIP 固定六文件清单和内嵌哈希通过验证。

- [ ] **Step 5: 独立核对桌面四个产物**

分别检查 APK/AAB/MSIX/ZIP 的完整路径、大小、修改时间和 SHA-256；再次读取 MSIX 清单、APK badging、APK/AAB/MSIX 签名，并核对 ZIP 内只含六个允许文件。

- [ ] **Step 6: 核对主工作区用户改动并本地合并**

确认主工作区仍只保留：

```text
lib/features/settings/presentation/k_settings_tile.dart
test/settings_presentation_components_test.dart
```

在不暂存这两处文件的前提下，把 `codex/android-anime4k-update-notes` 快进合并到 `main`；不推送远端。

- [ ] **Step 7: 最终状态检查**

Run: `git status --short`

Run: `git log -5 --oneline`

Run: `Get-AppxPackage -Name com.kanyingyin.player`

Expected: 主分支包含本轮提交；主工作区仍只有两处原有用户修改；当前已安装 Windows 版本仍为 `2.1.97.0`（未获授权不自动安装 2.1.98）。
