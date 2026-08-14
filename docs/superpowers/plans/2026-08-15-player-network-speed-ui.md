# 播放器网速显示与低速提示隐藏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Windows 与手机版 Android 的播放器在进度条下显示实时网速，并允许用户只对当前视频隐藏低速提示，最终交付 `2.1.160+20160` 测试版 EXE、APK 和 AAB。

**Architecture:** 复用现有 `CloudRangeRelayStatus`、`IVideoPageController` 和顶部状态展示链路，只新增一个纯 `PlayerNetworkSpeedPresenter`。低速可关闭语义与极小的关闭状态放在现有 `cloud_relay_status_presenter.dart`，`VideoPage` 负责当前视频身份和关闭按钮；两套控制栏只负责调用共享展示器并渲染一行文字。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、MobX、Flutter Modular、`flutter_test`、PowerShell、Inno Setup 6、Android Gradle、APK Signature Scheme v2、AAB JAR 签名。

---

## Ponytail 约束

本计划使用 `ponytail:ponytail` full：

- 只新增一个生产文件和一个测试文件。
- 不新增设置项、依赖、接口、工厂、Banner 组件或状态仓库。
- 复用现有 `CloudRelayStatusPresenter`、`IVideoPageController.relayStatus`、两套控制栏和发布脚本。
- 不修改网盘中转、缓存、并发、重连或播放器动画。
- 不更新 Inno Setup 脚本中的备用版本常量；正式构建脚本已经通过 `/DMyAppVersion` 传入实际版本。

## 文件结构

### 新建

- `lib/features/player/presentation/player_network_speed_presenter.dart`：将中转状态格式化为控制栏网速文字。
- `test/player_network_speed_presenter_test.dart`：覆盖正常速度和所有无效输入。

### 修改

- `lib/pages/video/cloud_relay_status_presenter.dart`：增加 `dismissible` 语义和当前视频关闭状态。
- `lib/pages/video/video_page.dart`：绑定播放身份、关闭低速提示并渲染关闭按钮。
- `lib/pages/player/player_item_panel.dart`：完整控制栏在进度条下显示网速。
- `lib/pages/player/smallest_player_item_panel.dart`：紧凑控制栏在进度条下显示网速。
- `test/cloud_relay_status_ui_test.dart`：覆盖通用低速可关闭语义与关闭状态。
- `test/quark_relay_status_ui_test.dart`：覆盖顶部关闭按钮和两套控制栏接线契约。
- `pubspec.yaml`、`lib/core/app_version.dart`、`android/app/build.gradle.kts`、`tool/android/build_signed_release.ps1`：同步 `2.1.160+20160`。
- `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`：增加普通用户可理解的测试版更新说明。
- `test/release_config_contract_test.dart`、`test/version_consistency_test.dart`、`test/version_history_current_test.dart`、`test/android_release_packaging_test.dart`、`test/android_tv_release_contract_test.dart`、`test/identity_v2_zero_residue_test.dart`：同步版本和发布契约。

## Task 1：执行版本更新前预检

**Files:**

- Read: `pubspec.yaml`
- Read: Windows 卸载注册表、已安装 `kanyingyin.exe`、当前用户 MSIX 状态
- No file changes

- [ ] **Step 1：确认独立分支和干净工作区**

Run:

```powershell
chcp 65001 > $null
git branch --show-current
git status --short
git log -2 --oneline
```

Expected: 分支为 `codex/player-network-speed-ui`，工作区为空，顶部包含已批准的设计提交 `5e5528d`。

- [ ] **Step 2：记录当前 EXE 安装与主程序版本**

Run:

```powershell
chcp 65001 > $null
$roots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$entries = foreach ($root in $roots) {
  Get-ItemProperty -Path $root -ErrorAction SilentlyContinue
}
$installed = @($entries | Where-Object {
  $_.DisplayName -eq '看影音' -or $_.DisplayName -like '看影音 *'
})
$installed | Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString

$exeCandidates = @(
  $installed.InstallLocation | Where-Object { $_ } | ForEach-Object {
    Join-Path $_ 'kanyingyin.exe'
  }
  'D:\看影音\kanyingyin.exe'
  (Join-Path $env:LOCALAPPDATA 'Programs\看影音\kanyingyin.exe')
) | Select-Object -Unique
$exeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
  ForEach-Object {
    $item = Get-Item -LiteralPath $_
    [PSCustomObject]@{
      Path = $item.FullName
      ProductVersion = $item.VersionInfo.ProductVersion
      FileVersion = $item.VersionInfo.FileVersion
    }
  }
```

Expected: 输出必须原样记录到本轮执行日志与最终交付报告；不得用 `pubspec.yaml` 猜测已安装版本。未安装时明确记录“未发现 EXE 安装”。

- [ ] **Step 3：记录旧 MSIX 是否仍存在**

Run:

```powershell
chcp 65001 > $null
$msix = @(Get-AppxPackage -Name 'com.kanyingyin.player' -ErrorAction SilentlyContinue)
if ($msix.Count -eq 0) {
  '未发现旧 MSIX'
} else {
  $msix | Select-Object Name, PackageFullName, Version, InstallLocation
}
```

Expected: 只查询，不卸载；把结果与 EXE 安装状态分开记录。

- [ ] **Step 4：确认锁定依赖和当前 Full Android 媒体包解析**

Run:

```powershell
chcp 65001 > $null
D:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile
Select-String -Path '.dart_tool\package_config.json' -Encoding UTF8 `
  -Pattern 'third_party/media_kit_libs_android_video_full'
```

Expected: `pub get` exit code 0，`package_config.json` 命中 `../third_party/media_kit_libs_android_video_full`。

- [ ] **Step 5：运行改动前基线测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart `
  test/embedded_track_controls_test.dart
```

Expected: `All tests passed!`。若基线失败，先记录并定位，不进入版本修改。

## Task 2：用 TDD 增加共享网速展示器

**Files:**

- Create: `lib/features/player/presentation/player_network_speed_presenter.dart`
- Create: `test/player_network_speed_presenter_test.dart`

- [ ] **Step 1：先写展示器失败测试**

Create `test/player_network_speed_presenter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/player_network_speed_presenter.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

void main() {
  test('有效网盘速度显示一位小数', () {
    const status = CloudRangeRelayStatus(
      providerName: '夸克',
      phase: CloudRangeRelayPhase.ready,
      bytesPerSecond: 4.3 * 1024 * 1024,
    );

    expect(PlayerNetworkSpeedPresenter.present(status), '网速 4.3 MB/s');
  });

  test('没有状态或速度无效时不显示网速', () {
    expect(PlayerNetworkSpeedPresenter.present(null), isNull);
    for (final speed in <double>[
      0,
      -1,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final status = CloudRangeRelayStatus(
        providerName: '夸克',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: speed,
      );
      expect(
        PlayerNetworkSpeedPresenter.present(status),
        isNull,
        reason: '$speed 不应生成网速文字',
      );
    }
  });
}
```

- [ ] **Step 2：运行测试并确认因缺少实现而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/player_network_speed_presenter_test.dart
```

Expected: FAIL，错误指向缺少 `player_network_speed_presenter.dart` 或 `PlayerNetworkSpeedPresenter`，不是测试语法错误。

- [ ] **Step 3：写最小展示器实现**

Create `lib/features/player/presentation/player_network_speed_presenter.dart`:

```dart
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

abstract final class PlayerNetworkSpeedPresenter {
  static String? present(CloudRangeRelayStatus? status) {
    final bytesPerSecond = status?.bytesPerSecond;
    if (bytesPerSecond == null ||
        !bytesPerSecond.isFinite ||
        bytesPerSecond <= 0) {
      return null;
    }
    final megabytes = bytesPerSecond / (1024 * 1024);
    return '网速 ${megabytes.toStringAsFixed(1)} MB/s';
  }
}
```

- [ ] **Step 4：格式化并确认测试转绿**

Run:

```powershell
D:\flutter\bin\dart.bat format `
  lib/features/player/presentation/player_network_speed_presenter.dart `
  test/player_network_speed_presenter_test.dart
D:\flutter\bin\flutter.bat test --no-pub test/player_network_speed_presenter_test.dart
```

Expected: `All tests passed!`。

- [ ] **Step 5：提交共享展示器**

Run:

```powershell
git add -- `
  lib/features/player/presentation/player_network_speed_presenter.dart `
  test/player_network_speed_presenter_test.dart
git diff --cached --check
git commit -m '功能：格式化播放器实时网速'
```

Expected: 只提交上述两个文件。

## Task 3：用 TDD 增加低速可关闭语义和最小状态

**Files:**

- Modify: `lib/pages/video/cloud_relay_status_presenter.dart:3`
- Modify: `test/cloud_relay_status_ui_test.dart:20`
- Modify: `test/quark_relay_status_ui_test.dart:20`

- [ ] **Step 1：先补低速语义和关闭状态测试**

在两个现有低速测试中分别增加：

```dart
expect(presentation.dismissible, isTrue);
```

在 `test/cloud_relay_status_ui_test.dart` 增加：

```dart
test('关闭状态只隐藏同一视频的低速提示', () {
  final lowSpeed = CloudRelayStatusPresenter.present(
    const CloudRangeRelayStatus(
      providerName: '夸克网盘',
      phase: CloudRangeRelayPhase.degraded,
      bytesPerSecond: 4 * 1024 * 1024,
    ),
  );
  final failed = CloudRelayStatusPresenter.present(
    const CloudRangeRelayStatus(
      providerName: '夸克网盘',
      phase: CloudRangeRelayPhase.failed,
    ),
  );
  final dismissal = CloudRelayStatusDismissal();

  dismissal.dismiss('cloud:episode-1');

  expect(dismissal.hides(lowSpeed, 'cloud:episode-1'), isTrue);
  expect(dismissal.hides(lowSpeed, 'cloud:episode-2'), isFalse);
  expect(dismissal.hides(failed, 'cloud:episode-1'), isFalse);

  dismissal.clear();
  expect(dismissal.hides(lowSpeed, 'cloud:episode-1'), isFalse);
});
```

把 `test/quark_relay_status_ui_test.dart` 的“重连和失败状态”测试替换为：

```dart
test('重连和失败状态使用明确文案且不可按低速规则关闭', () {
  final reconnecting = CloudRelayStatusPresenter.present(
    const CloudRangeRelayStatus(
      providerName: '夸克',
      phase: CloudRangeRelayPhase.reconnecting,
    ),
  );
  final failed = CloudRelayStatusPresenter.present(
    const CloudRangeRelayStatus(
      providerName: '夸克',
      phase: CloudRangeRelayPhase.failed,
    ),
  );

  expect(reconnecting.text, '夸克正在重新连接');
  expect(reconnecting.dismissible, isFalse);
  expect(failed.text, '夸克分段读取失败');
  expect(failed.dismissible, isFalse);
});
```

- [ ] **Step 2：运行测试并确认缺少成员**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart
```

Expected: FAIL，缺少 `dismissible` 或 `CloudRelayStatusDismissal`。

- [ ] **Step 3：在现有展示文件中写最小实现**

把 `CloudRelayStatusPresentation` 构造函数改为：

```dart
class CloudRelayStatusPresentation {
  const CloudRelayStatusPresentation({
    required this.text,
    required this.warning,
    required this.stable,
    this.dismissible = false,
  });

  final String text;
  final bool warning;
  final bool stable;
  final bool dismissible;
}
```

在低速分支增加：

```dart
return CloudRelayStatusPresentation(
  text: withDetails('当前网盘读取速度不足'),
  warning: true,
  stable: false,
  dismissible: true,
);
```

在同一文件末尾增加最小状态类：

```dart
class CloudRelayStatusDismissal {
  String? _dismissedPlaybackIdentity;

  void dismiss(String playbackIdentity) {
    _dismissedPlaybackIdentity = playbackIdentity;
  }

  void clear() {
    _dismissedPlaybackIdentity = null;
  }

  bool hides(
    CloudRelayStatusPresentation presentation,
    String playbackIdentity,
  ) {
    return presentation.dismissible &&
        _dismissedPlaybackIdentity == playbackIdentity;
  }
}
```

- [ ] **Step 4：格式化并确认测试转绿**

Run:

```powershell
D:\flutter\bin\dart.bat format `
  lib/pages/video/cloud_relay_status_presenter.dart `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart
D:\flutter\bin\flutter.bat test --no-pub `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart
```

Expected: `All tests passed!`。

- [ ] **Step 5：提交状态语义**

Run:

```powershell
git add -- `
  lib/pages/video/cloud_relay_status_presenter.dart `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart
git diff --cached --check
git commit -m '功能：定义低速提示关闭规则'
```

## Task 4：用 TDD 接入顶部关闭按钮

**Files:**

- Modify: `lib/pages/video/video_page.dart:46,218,700`
- Modify: `test/quark_relay_status_ui_test.dart:75`

- [ ] **Step 1：先写页面接线失败测试**

在 `test/quark_relay_status_ui_test.dart` 增加：

```dart
test('播放器允许只隐藏当前视频的低速提示', () {
  final page = File('lib/pages/video/video_page.dart').readAsStringSync();

  expect(page, contains('CloudRelayStatusDismissal'));
  expect(page, contains('_relayStatusDismissal.hides'));
  expect(
    page,
    contains("const ValueKey<String>('cloud-relay-dismiss-button')"),
  );
  expect(page, contains("tooltip: '隐藏本视频低速提示'"));
  expect(page, contains('ignoring: !visible'));
});
```

- [ ] **Step 2：运行测试并确认接线尚不存在**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/quark_relay_status_ui_test.dart
```

Expected: FAIL，缺少 `CloudRelayStatusDismissal` 页面接线或关闭按钮 key。

- [ ] **Step 3：增加当前播放身份与关闭状态**

在 `_VideoPageState` 字段区增加：

```dart
final CloudRelayStatusDismissal _relayStatusDismissal =
    CloudRelayStatusDismissal();
```

在 `_relayPresentation` 前增加：

```dart
String get _relayPlaybackIdentity =>
    localVideoController.currentPlaybackHistoryKey ??
    'relay-session:${localVideoController.currentEpisode}:'
        '${localVideoController.currentRoad}';
```

在 `changeEpisode` 开头保存旧身份，并在成功返回后只对实际身份变化清除状态：

```dart
final previousPlaybackIdentity = _relayPlaybackIdentity;
```

把原来的尾部：

```dart
await localVideoController.changeEpisode(episode,
    currentRoad: currentRoad, offset: offset);
if (mounted) setState(() {});
```

替换为：

```dart
await localVideoController.changeEpisode(
  episode,
  currentRoad: currentRoad,
  offset: offset,
);
if (previousPlaybackIdentity != _relayPlaybackIdentity) {
  _relayStatusDismissal.clear();
}
if (mounted) setState(() {});
```

- [ ] **Step 4：把顶部状态块改为可交互的最小横向布局**

在 `Observer` 中计算：

```dart
final playbackIdentity = _relayPlaybackIdentity;
final dismissed = presentation != null &&
    _relayStatusDismissal.hides(presentation, playbackIdentity);
final visible = presentation != null &&
    !dismissed &&
    !_relayStatusHidden &&
    !localVideoController.loading &&
    !playerController.loading;
final foregroundColor = presentation?.warning == true
    ? Theme.of(context).colorScheme.onErrorContainer
    : Colors.white;
```

把原有 `IgnorePointer` 和 `Container` 内容替换为：

```dart
return IgnorePointer(
  ignoring: !visible,
  child: AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: StyleString.fastAnimationDuration,
    curve: StyleString.defaultCurve,
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: presentation?.warning == true
              ? Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.92)
              : Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              presentation?.text ?? '',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            if (presentation?.dismissible == true)
              IconButton(
                key: const ValueKey<String>('cloud-relay-dismiss-button'),
                tooltip: '隐藏本视频低速提示',
                color: foregroundColor,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _relayStatusDismissal.dismiss(playbackIdentity);
                  });
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
      ),
    ),
  ),
);
```

- [ ] **Step 5：格式化并确认页面契约转绿**

Run:

```powershell
D:\flutter\bin\dart.bat format `
  lib/pages/video/video_page.dart `
  test/quark_relay_status_ui_test.dart
D:\flutter\bin\flutter.bat test --no-pub `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart
```

Expected: `All tests passed!`。

- [ ] **Step 6：提交顶部提示交互**

Run:

```powershell
git add -- lib/pages/video/video_page.dart test/quark_relay_status_ui_test.dart
git diff --cached --check
git commit -m '功能：允许隐藏当前视频低速提示'
```

## Task 5：用 TDD 在两套控制栏显示网速

**Files:**

- Modify: `lib/pages/player/player_item_panel.dart:570`
- Modify: `lib/pages/player/smallest_player_item_panel.dart:475`
- Modify: `test/quark_relay_status_ui_test.dart:75`

- [ ] **Step 1：先写两套控制栏接线失败测试**

在 `test/quark_relay_status_ui_test.dart` 增加：

```dart
test('完整和紧凑控制栏共用实时网速展示器', () {
  final expectedKeys = <String>[
    'full-player-network-speed',
    'compact-player-network-speed',
  ];
  final paths = <String>[
    'lib/pages/player/player_item_panel.dart',
    'lib/pages/player/smallest_player_item_panel.dart',
  ];

  for (var index = 0; index < paths.length; index++) {
    final source = File(paths[index]).readAsStringSync();
    expect(source, contains('PlayerNetworkSpeedPresenter.present'));
    expect(source, contains(expectedKeys[index]));
    expect(source, contains('videoPageController.relayStatus'));
  }
});
```

- [ ] **Step 2：运行测试并确认控制栏尚未接入**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/quark_relay_status_ui_test.dart
```

Expected: FAIL，两套文件均缺少 `PlayerNetworkSpeedPresenter.present`。

- [ ] **Step 3：接入完整控制栏**

在 `player_item_panel.dart` 增加 import：

```dart
import 'package:kanyingyin/features/player/presentation/player_network_speed_presenter.dart';
```

在 `bottomControlWidget` 的 `Observer` 内、`return SafeArea` 前增加：

```dart
final networkSpeedText = PlayerNetworkSpeedPresenter.present(
  videoPageController.relayStatus,
);
```

在进度条 `Padding` 后、按钮行 `Padding` 前增加：

```dart
if (networkSpeedText != null)
  Padding(
    key: const ValueKey<String>('full-player-network-speed'),
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
    child: Text(
      networkSpeedText,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  ),
```

- [ ] **Step 4：接入紧凑控制栏**

在 `smallest_player_item_panel.dart` 增加相同展示器 import，并在 `Observer` 内、`return Row` 前增加：

```dart
final networkSpeedText = PlayerNetworkSpeedPresenter.present(
  videoPageController.relayStatus,
);
```

把紧凑控制栏中只包含 `ProgressBar` 的 `Expanded` 替换为：

```dart
Expanded(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ProgressBar(
        thumbRadius: 8,
        thumbGlowRadius: 18,
        timeLabelLocation: TimeLabelLocation.none,
        progress: playerController.currentPosition,
        buffered: playerController.buffer,
        total: playerController.duration,
        onSeek: (duration) {
          playerController.seek(duration);
        },
        onDragStart: (details) {
          widget.handleProgressBarDragStart(details);
        },
        onDragUpdate: (details) =>
            {playerController.currentPosition = details.timeStamp},
        onDragEnd: () {
          widget.handleProgressBarDragEnd();
        },
      ),
      if (networkSpeedText != null)
        Padding(
          key: const ValueKey<String>('compact-player-network-speed'),
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            networkSpeedText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
    ],
  ),
),
```

- [ ] **Step 5：格式化并确认控制栏测试转绿**

Run:

```powershell
D:\flutter\bin\dart.bat format `
  lib/pages/player/player_item_panel.dart `
  lib/pages/player/smallest_player_item_panel.dart `
  test/quark_relay_status_ui_test.dart
D:\flutter\bin\flutter.bat test --no-pub `
  test/player_network_speed_presenter_test.dart `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart `
  test/embedded_track_controls_test.dart
```

Expected: `All tests passed!`。

- [ ] **Step 6：提交控制栏网速行**

Run:

```powershell
git add -- `
  lib/pages/player/player_item_panel.dart `
  lib/pages/player/smallest_player_item_panel.dart `
  test/quark_relay_status_ui_test.dart
git diff --cached --check
git commit -m '功能：在进度条下显示实时网速'
```

## Task 6：用 TDD 同步 2.1.160 测试版版本与文案

**Files:**

- Modify: `pubspec.yaml:19,144`
- Modify: `lib/core/app_version.dart:5`
- Modify: `android/app/build.gradle.kts:42-47`
- Modify: `tool/android/build_signed_release.ps1:62-66`
- Modify: `RELEASE_NOTES.md:3`
- Modify: `UPDATE_DIALOG_COPY.md:5`
- Modify: `lib/utils/version_history.dart:181`
- Modify: six release contract tests listed in the file map

- [ ] **Step 1：先把发布契约测试切换到 2.1.160**

在以下测试中把当前测试版的 `2.1.159`/`20159` 精确更新为 `2.1.160`/`20160`：

```text
test/release_config_contract_test.dart
test/version_consistency_test.dart
test/version_history_current_test.dart
test/android_release_packaging_test.dart
test/android_tv_release_contract_test.dart
test/identity_v2_zero_residue_test.dart
```

同时完成以下精确改名和数值更新：

```text
release_config_contract_test.dart：测试名改为“当前发布配置为二点一六零 Windows 与 Android 手机测试版”。
version_consistency_test.dart：测试名改为“二点一六零 Windows 与 Android 手机测试版版本文案保持一致”。
android_release_packaging_test.dart：mobile Release 测试名改为“Android mobile 二点一六零测试版并使用本机环境签名”。
android_tv_release_contract_test.dart：首个测试名改为“Android mobile 二点一六零测试版并仅保留 tvTest 源码 flavor”。
identity_v2_zero_residue_test.dart：currentVersion 期望改为 2.1.160，build number 期望改为 20160。
```

`release_config_contract_test.dart` 的当前说明范围必须使用：

```dart
final releaseNotesStart = releaseNotes.indexOf('## 2.1.160+20160');
final releaseNotesEnd = releaseNotes.indexOf('\n## 2.1.159+20159');
```

把 `release_config_contract_test.dart` 顶部文案常量替换为：

```dart
const _networkSpeedCopy =
    '播放网盘视频时，进度条下方会显示实时网速，控制栏收起后同步隐藏。';
```

该测试对 `currentReleaseNotes` 增加：

```dart
for (final text in <String>[
  '进度条',
  '实时网速',
  '当前视频',
  '重新连接',
  '读取失败',
  '不会修改或删除',
]) {
  expect(currentReleaseNotes, contains(text));
}
expect(currentReleaseNotes, contains(_networkSpeedCopy));
expect(updateDialogCopy, contains(_networkSpeedCopy));
expect(currentReleaseNotes, isNot(contains('网速提升')));
```

删除该测试仅属于 2.1.159 的“高刷新率、天玑 930、夸克原画、诊断日志、4K HDR 120 帧”断言。

`version_consistency_test.dart` 对现有 `currentReleaseNotes`、`currentVersionHistory` 循环使用：

```dart
for (final text in <String>[
  '进度条',
  '实时网速',
  '当前视频',
  '重新连接',
  '读取失败',
  '不会修改或删除',
]) {
  expect(currentCopy, contains(text));
}
for (final unsupportedClaim in <String>[
  '网速提升',
  '保证达到',
  'Android TV',
  'tvTest',
]) {
  expect(currentCopy, isNot(contains(unsupportedClaim)));
}
```

删除该测试仅属于 2.1.159 的高刷新率和硬件样本断言，保留测试版、Windows/Android 手机版、TV 排除、文件安全与正式版 README 契约。

`version_history_current_test.dart` 的首个测试改为：

```dart
test('二点一六零说明实时网速和当前视频低速提示隐藏', () {
  final entries = versionHistoryForCurrent(
    '2.1.160',
    platform: AppPlatformKind.android,
  );

  expect(entries, hasLength(1));
  expect(entries.single.version, '2.1.160');
  expect(entries.single.isPrerelease, isTrue);
  final changes = entries.single.changes.join('\n');
  for (final text in <String>[
    'Android 手机',
    '进度条',
    '实时网速',
    '当前视频',
    '重新连接',
    '读取失败',
    '不会修改或删除',
  ]) {
    expect(changes, contains(text));
  }
  for (final unsupportedClaim in <String>[
    '网速提升',
    '保证达到',
    'Android TV',
    'tvTest',
  ]) {
    expect(changes, isNot(contains(unsupportedClaim)));
  }
});
```

- [ ] **Step 2：运行发布契约并确认因源码仍是 2.1.159 而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/android_release_packaging_test.dart `
  test/android_tv_release_contract_test.dart `
  test/identity_v2_zero_residue_test.dart
```

Expected: FAIL，实际值仍为 `2.1.159+20159`。

- [ ] **Step 3：同步所有版本源**

使用精确补丁更新：

```yaml
# pubspec.yaml
version: 2.1.160+20160
msix_config:
  msix_version: 2.1.160.0
```

```dart
// lib/core/app_version.dart
static const String current = '2.1.160';
```

```kotlin
// android/app/build.gradle.kts
if (pubspecVersionMatch.groupValues[1] != "2.1.160" ||
    pubspecVersionMatch.groupValues[2] != "20160") {
    throw GradleException("Windows pubspec 版本必须为 2.1.160+20160")
}
val androidVersionName = "2.1.160"
val androidVersionCode = 20160
```

```powershell
# tool/android/build_signed_release.ps1
if ($pubspecVersion.Name -ne '2.1.160' -or $pubspecVersion.Code -ne 20160) {
    throw "Windows pubspec 版本必须为 2.1.160+20160，实际为 $($pubspecVersion.Name)+$($pubspecVersion.Code)"
}
$androidVersion = '2.1.160'
$androidVersionCode = 20160
```

- [ ] **Step 4：增加 2.1.160 用户文案**

在 `RELEASE_NOTES.md` 顶部加入：

```markdown
## 2.1.160+20160

Windows EXE 安装器版本：2.1.160

APK/AAB 版本：2.1.160 (20160)

### Windows 和 Android 手机测试版更新内容

标题：看影音 2.1.160 测试版

- 播放网盘视频时，进度条下方会显示实时网速，控制栏收起后同步隐藏。
- 检测到网盘读取速度不足时，可以关闭提示；关闭只对当前视频生效，切换视频后自动恢复。
- 当前视频发生重新连接或读取失败时仍会显示必要提示，避免隐藏重要错误。
- 本次更新只调整播放器状态展示，不改变网盘读取、缓存或重连策略。
- 本次更新不会修改或删除，也不会改名、移动本地及个人网盘原始视频和字幕。
```

在 `versionHistoryList` 顶部加入：

```dart
VersionHistory(
  version: '2.1.160',
  date: '2026-08-15',
  isPrerelease: true,
  changes: [
    'Windows 2.1.160 测试版与 Android 手机使用同一版本；播放网盘视频时，进度条下方会显示实时网速',
    '实时网速会随播放器控制栏一起显示和隐藏，不影响本地视频播放界面',
    '检测到网盘读取速度不足时可以关闭提示；关闭只对当前视频生效，切换视频后自动恢复',
    '当前视频发生重新连接或读取失败时仍会显示必要提示，避免隐藏重要错误',
    '本次更新只调整播放器状态展示，不改变网盘读取、缓存或重连策略',
    '本次更新不会修改或删除，也不会改名、移动本地及个人网盘原始视频和字幕',
  ],
),
```

把 `UPDATE_DIALOG_COPY.md` 当前版本区更新为：

```markdown
## 当前版本

- 应用版本：2.1.160
- Windows EXE 安装器版本：2.1.160 测试版
- 本轮交付：Windows 测试版 EXE 与 Android 手机 APK/AAB
- Android 应用版本：2.1.160
- Android versionCode：20160
- Android TV 继续暂停，不在本轮交付范围
- 日期：2026-08-15

## 弹窗标题

看影音 2.1.160 测试版

## Windows 弹窗正文

- 播放网盘视频时，进度条下方会显示实时网速，控制栏收起后同步隐藏。
- 检测到网盘读取速度不足时，可以关闭提示；关闭只对当前视频生效，切换视频后自动恢复。
- 当前视频发生重新连接或读取失败时仍会显示必要提示，避免隐藏重要错误。
- 本次更新只调整播放器状态展示，不改变网盘读取、缓存或重连策略。
- 本次更新不会修改或删除，也不会改名、移动本地及个人网盘原始视频和字幕。

## Android 弹窗正文

### 弹窗标题

看影音 Android 2.1.160 测试版

- 播放网盘视频时，进度条下方会显示实时网速，控制栏收起后同步隐藏。
- 检测到网盘读取速度不足时，可以关闭提示；关闭只对当前视频生效，切换视频后自动恢复。
- 当前视频发生重新连接或读取失败时仍会显示必要提示，避免隐藏重要错误。
- 本次更新只调整播放器状态展示，不改变网盘读取、缓存或重连策略。
- 本次更新不会修改或删除，也不会改名、移动本地及个人网盘原始视频和字幕。
```

保留该文件现有“按钮文字”和“维护要求”区块。

- [ ] **Step 5：格式化并确认版本契约转绿**

Run:

```powershell
D:\flutter\bin\dart.bat format `
  lib/core/app_version.dart `
  lib/utils/version_history.dart `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/android_release_packaging_test.dart `
  test/android_tv_release_contract_test.dart `
  test/identity_v2_zero_residue_test.dart
D:\flutter\bin\flutter.bat test --no-pub `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/android_release_packaging_test.dart `
  test/android_tv_release_contract_test.dart `
  test/identity_v2_zero_residue_test.dart
```

Expected: `All tests passed!`，且当前版文案不包含 TV 交付或网速提升承诺。

- [ ] **Step 6：提交测试版版本与文案**

Run:

```powershell
git add -- `
  pubspec.yaml `
  lib/core/app_version.dart `
  android/app/build.gradle.kts `
  tool/android/build_signed_release.ps1 `
  RELEASE_NOTES.md `
  UPDATE_DIALOG_COPY.md `
  lib/utils/version_history.dart `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/android_release_packaging_test.dart `
  test/android_tv_release_contract_test.dart `
  test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m '发布：准备2.1.160播放器网速测试版'
```

## Task 7：运行完整代码质量门禁

**Files:**

- Verify only; no expected source changes

- [ ] **Step 1：确认格式、差异和依赖状态**

Run:

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
git diff --check
git status --short
Select-String -Path '.dart_tool\package_config.json' -Encoding UTF8 `
  -Pattern 'third_party/media_kit_libs_android_video_full'
```

Expected: format 和 diff check exit code 0，工作区为空，Full Android 媒体包路径仍正确。

- [ ] **Step 2：重新运行全部相关定向测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test/player_network_speed_presenter_test.dart `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart `
  test/embedded_track_controls_test.dart `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/android_release_packaging_test.dart `
  test/android_tv_release_contract_test.dart `
  test/identity_v2_zero_residue_test.dart `
  test/windows_installer_contract_test.dart
```

Expected: `All tests passed!`。

- [ ] **Step 3：运行完整测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub --concurrency=8 --reporter compact
```

Expected: exit code 0，输出 `All tests passed!`；记录实际测试数量。

- [ ] **Step 4：运行完整静态分析**

Run:

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: exit code 0，输出 `No issues found!`。

## Task 8：构建并验证 Windows 2.1.160 测试版 EXE

**Files:**

- Build output: `build/windows/x64/runner/Release/kanyingyin.exe`
- Desktop output: `%USERPROFILE%\Desktop\看影音-2.1.160-测试版-安装程序.exe`
- No install, no MSIX

- [ ] **Step 1：构建 Windows Release**

Run:

```powershell
chcp 65001 > $null
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: exit code 0，生成 `build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 2：复用 Release 目录生成 Inno Setup 测试版安装器**

Run:

```powershell
chcp 65001 > $null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool\windows\build_exe_release.ps1 -SkipBuild
```

Expected: 输出 `Version=2.1.160`、Release 主程序路径、桌面安装器路径、SHA-256 和实际签名状态；文件名精确为 `看影音-2.1.160-测试版-安装程序.exe`。

- [ ] **Step 3：独立核对主程序与安装器**

Run:

```powershell
chcp 65001 > $null
$releaseExe = 'D:\KanYingYin\build\windows\x64\runner\Release\kanyingyin.exe'
$installer = Join-Path $env:USERPROFILE `
  'Desktop\看影音-2.1.160-测试版-安装程序.exe'
$release = Get-Item -LiteralPath $releaseExe
$package = Get-Item -LiteralPath $installer
$signature = Get-AuthenticodeSignature -LiteralPath $installer
[PSCustomObject]@{
  ReleaseProductVersion = $release.VersionInfo.ProductVersion
  InstallerProductVersion = $package.VersionInfo.ProductVersion
  InstallerLength = $package.Length
  InstallerSHA256 = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
  SignatureStatus = $signature.Status
  SignerSubject = $signature.SignerCertificate.Subject
}
if ($release.VersionInfo.ProductVersion -ne '2.1.160') {
  throw 'Windows Release 主程序版本不等于 2.1.160'
}
if (-not $package.VersionInfo.ProductVersion.StartsWith('2.1.160')) {
  throw 'Windows 安装器版本不等于 2.1.160'
}
```

Expected: 两个版本检查通过。签名状态按实际输出记录；测试版脚本未强制签名时不得宣称安装器已签名。

- [ ] **Step 4：保持未安装状态**

不运行安装器。最终报告把“包验证通过”与“未执行安装/运行时验证”分开列出。

## Task 9：构建并验证 Android mobile 2.1.160 APK/AAB

**Files:**

- Build APK: `build/app/outputs/flutter-apk/app-mobile-release.apk`
- Build AAB: `build/app/outputs/bundle/mobileRelease/app-mobile-release.aab`
- Desktop APK: `%USERPROFILE%\Desktop\看影音-2.1.160.apk`
- Desktop AAB: `%USERPROFILE%\Desktop\看影音-2.1.160.aab`
- No `tvTest` command or artifact

- [ ] **Step 1：运行现有 mobile 签名构建脚本**

Run:

```powershell
chcp 65001 > $null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool\android\build_signed_release.ps1 -Flavor mobile
```

Expected: APK 和 AAB 构建成功；脚本验证包名 `com.kanyingyin.player`、`versionName=2.1.160`、`versionCode=20160`、APK v2 签名、AAB strict 签名以及 Full `libmpv.so`，随后复制两个桌面文件。

- [ ] **Step 2：再次独立验证 Full 媒体内容**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool\android\verify_full_media_bundle.ps1 `
  -PackageKind apk `
  -PackagePath build\app\outputs\flutter-apk\app-mobile-release.apk
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool\android\verify_full_media_bundle.ps1 `
  -PackageKind aab `
  -PackagePath build\app\outputs\bundle\mobileRelease\app-mobile-release.aab
```

Expected: `arm64-v8a`、`armeabi-v7a`、`x86_64` 均输出 `Full libmpv verified`。

- [ ] **Step 3：比较构建产物与桌面副本哈希**

Run:

```powershell
chcp 65001 > $null
$pairs = @(
  @(
    'D:\KanYingYin\build\app\outputs\flutter-apk\app-mobile-release.apk',
    (Join-Path $env:USERPROFILE 'Desktop\看影音-2.1.160.apk')
  ),
  @(
    'D:\KanYingYin\build\app\outputs\bundle\mobileRelease\app-mobile-release.aab',
    (Join-Path $env:USERPROFILE 'Desktop\看影音-2.1.160.aab')
  )
)
foreach ($pair in $pairs) {
  $sourceHash = (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash
  $desktopHash = (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash
  [PSCustomObject]@{
    Source = $pair[0]
    Desktop = $pair[1]
    SHA256 = $sourceHash
    Equal = $sourceHash -eq $desktopHash
  }
  if ($sourceHash -ne $desktopHash) {
    throw "桌面 Android 产物哈希不一致：$($pair[1])"
  }
}
```

Expected: 两项 `Equal=True`，记录两个 SHA-256。

- [ ] **Step 4：确认没有运行 TV 发布流程**

Run:

```powershell
git status --short
```

Expected: 没有 TV 版本、TV 资源或 TV 发布记录改动。本任务不得调用 `build_tv_test.ps1`、`build_personal_tv.ps1` 或 `-Flavor tvTest`。

## Task 10：最终差异和交付状态审计

**Files:**

- Verify committed source, tests, docs and desktop artifacts
- No remote write

- [ ] **Step 1：核对提交范围与工作区**

Run:

```powershell
chcp 65001 > $null
git status --short
git log --oneline main..HEAD
git diff --check main...HEAD
git diff --stat main...HEAD
```

Expected: 工作区为空；分支只包含设计、网速 UI、版本文案及相关测试提交，没有证书、密钥、构建目录或 TV 产物。

- [ ] **Step 2：逐项核对需求**

核对并在最终报告分开列出：

```text
代码行为：低速提示可按当前视频关闭；重连/失败仍显示；切换视频恢复。
控制栏：完整和紧凑布局均在进度条下显示网速；本地/无效速度不显示。
源码门禁：定向测试、完整测试、静态分析。
Windows 构建：Release 主程序、Inno EXE、版本、SHA-256、实际签名状态。
Android 构建：mobile APK/AAB、版本、签名、Full libmpv、桌面哈希。
未执行：安装、Windows/Android 实机可见 UI 验收、TV 构建、远端推送、GitHub Release。
```

- [ ] **Step 3：只在验证修复产生新改动时补交一次提交**

Expected: 正常情况下无需执行。若 Task 7-9 为修复真实失败而修改了本轮文件，重新运行受影响门禁后，只暂存这些修复并提交：

```powershell
git add -- `
  lib/features/player/presentation/player_network_speed_presenter.dart `
  lib/pages/video/cloud_relay_status_presenter.dart `
  lib/pages/video/video_page.dart `
  lib/pages/player/player_item_panel.dart `
  lib/pages/player/smallest_player_item_panel.dart `
  test/player_network_speed_presenter_test.dart `
  test/cloud_relay_status_ui_test.dart `
  test/quark_relay_status_ui_test.dart `
  pubspec.yaml `
  lib/core/app_version.dart `
  android/app/build.gradle.kts `
  tool/android/build_signed_release.ps1 `
  RELEASE_NOTES.md `
  UPDATE_DIALOG_COPY.md `
  lib/utils/version_history.dart `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/android_release_packaging_test.dart `
  test/android_tv_release_contract_test.dart `
  test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m '修复：完善播放器网速测试版验证'
```

不得暂存构建产物、桌面文件、证书、密钥或无关改动。
