# 轨道语言确认不中断播放实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标：** 修复未识别轨道在播放初始化阶段强制弹窗并阻断字幕挂载的问题，让用户先看到字幕，再按需确认语言，同时保证播放器退出键和原有播放行为不受影响。

**架构：** `PlayerController` 继续负责轨道识别、默认选轨和本地持久化；未解析轨道不再阻断 `_selectDefaultEmbeddedTracks`。`PlayerItem` 移除按 revision 自动弹窗，改为仅响应字幕/音轨菜单发起的单轨确认；确认窗口可取消且不触碰播放器生命周期。菜单通过显式回调把当前轨道交给 `PlayerItem`，避免 UI 组件直接管理播放器状态。

**技术栈：** Flutter、MobX、media_kit、Flutter widget test、Dart build_runner。

---

### 任务 1：为不中断播放和可关闭确认建立失败测试

**文件：**
- 修改：`test/local_video_controller_test.dart`
- 修改：`test/track_language_confirmation_dialog_test.dart`
- 创建：`test/embedded_track_menus_test.dart`

- [ ] **步骤 1：补充控制器源代码回归断言**

在 `local_video_controller_test.dart` 增加测试，读取 `player_controller.dart` 并断言 `_selectDefaultEmbeddedTracks` 不再包含 `if (pendingTrackLanguages.isNotEmpty) return;`，同时保留 `selectEmbeddedSubtitleTrack(subtitle.id, manual: false)` 调用。

- [ ] **步骤 2：补充播放器不自动弹窗断言**

在同一测试文件中，将旧的 `barrierDismissible: false` 断言替换为以下行为断言：

```dart
expect(item, isNot(contains('_scheduleTrackLanguageConfirmation')));
expect(item, contains('barrierDismissible: true'));
expect(item, contains('稍后确认'));
```

- [ ] **步骤 3：运行测试确认红灯**

运行：

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'; D:\flutter\bin\flutter.bat test test/local_video_controller_test.dart test/track_language_confirmation_dialog_test.dart
```

预期：失败原因是当前代码仍然提前返回、自动调度确认且弹窗不可关闭。

- [ ] **步骤 4：补充确认窗口关闭测试**

在 `track_language_confirmation_dialog_test.dart` 添加 widget 测试：点击 `稍后确认` 后 `Navigator.pop`，断言 `onConfirm` 未被调用；再用 `tester.tapAt(const Offset(10, 10))` 验证遮罩可以关闭。

- [ ] **步骤 5：提交测试基线**

```powershell
git add test/local_video_controller_test.dart test/track_language_confirmation_dialog_test.dart test/embedded_track_menus_test.dart
git commit -m "test: 覆盖轨道语言确认不中断播放"
```

### 任务 2：解除控制器对未解析轨道的播放阻断

**文件：**
- 修改：`lib/pages/player/player_controller.dart:1282-1315`
- 修改：`test/local_video_controller_test.dart`

- [ ] **步骤 1：删除待确认提前返回**

从 `_selectDefaultEmbeddedTracks` 删除：

```dart
if (pendingTrackLanguages.isNotEmpty) return;
```

其余自动选择状态机、generation 检查和 `currentSubtitlePath` 互斥逻辑保持不变。

- [ ] **步骤 2：增加单轨确认方法**

在 `confirmTrackLanguages` 前新增 MobX action：

```dart
@action
Future<String?> confirmTrackLanguage(
  int revision,
  String fingerprint,
  TrackLanguageChoice choice,
) async
```

方法必须先用 `_trackLanguageConfirmationState.canApply(revision, mediaKey)` 校验；保存单条指纹；再次校验 generation；只更新匹配的音频或字幕项并从 `pendingTrackLanguages` 移除该项。关闭/稍后确认不调用此方法。保存成功后只刷新菜单状态，不调用 `_selectDefaultEmbeddedTracks`。

- [ ] **步骤 3：运行控制器测试确认绿灯**

运行同任务 1 的 flutter test 命令，预期控制器相关测试通过。

- [ ] **步骤 4：提交控制器修复**

```powershell
git add lib/pages/player/player_controller.dart test/local_video_controller_test.dart
git commit -m "fix: 未确认轨道不阻断字幕播放"
```

### 任务 3：将确认入口移到字幕/音轨菜单

**文件：**
- 修改：`lib/pages/player/widgets/embedded_track_menus.dart`
- 修改：`lib/pages/player/player_item_panel.dart`
- 修改：`lib/pages/player/smallest_player_item_panel.dart`
- 修改：`lib/pages/player/player_item.dart`
- 修改：`test/embedded_track_menus_test.dart`

- [ ] **步骤 1：扩展菜单回调**

给 `EmbeddedTrackMenus` 增加必填回调：

```dart
final void Function(EmbeddedTrackInfo track) onConfirmTrackLanguage;
```

每条 `!track.isLanguageResolved` 的字幕或音轨后增加菜单项“确认语言”，点击时调用该回调；原有轨道项仍只负责切轨，标题、详情和选中状态不变。

- [ ] **步骤 2：贯穿两个播放器面板**

给 `PlayerItemPanel` 与 `SmallestPlayerItemPanel` 增加同名必填回调，并在各自创建 `EmbeddedTrackMenus` 时转发。`PlayerItem` 构建面板时传入 `_showTrackLanguageConfirmationForTrack`。

- [ ] **步骤 3：添加菜单测试**

使用一条未解析字幕轨道构建 `EmbeddedTrackMenus`，断言“确认语言”出现；点击后回调收到相同的 `EmbeddedTrackInfo`。已解析轨道不出现该入口。

- [ ] **步骤 4：运行菜单测试**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'; D:\flutter\bin\flutter.bat test test/embedded_track_menus_test.dart
```

- [ ] **步骤 5：提交菜单入口**

```powershell
git add lib/pages/player/widgets/embedded_track_menus.dart lib/pages/player/player_item_panel.dart lib/pages/player/smallest_player_item_panel.dart lib/pages/player/player_item.dart test/embedded_track_menus_test.dart
git commit -m "feat: 从轨道菜单确认语言"
```

### 任务 4：改造播放器确认窗口为按需、可关闭、单轨处理

**文件：**
- 修改：`lib/pages/player/player_item.dart:100-155,1220-1240`
- 修改：`lib/pages/player/widgets/track_language_confirmation_dialog.dart`
- 修改：`test/track_language_confirmation_dialog_test.dart`
- 修改：`test/local_video_controller_test.dart`

- [ ] **步骤 1：移除自动弹窗 reaction**

删除 `_trackLanguageConfirmationListener`、`_shownTrackLanguageRevision`、`_trackLanguageDialogOpen`、`_scheduleTrackLanguageConfirmation` 及 initState 中对应 reaction。保留 `_canUsePlayer` 和退出时停止计时器/输入的逻辑。

- [ ] **步骤 2：添加按轨道打开确认方法**

在 `PlayerItem` state 增加：

```dart
Future<void> _showTrackLanguageConfirmationForTrack(
  EmbeddedTrackInfo track,
) async
```

从控制器按轨道类型和 ID 找到对应 `PendingTrackLanguage`；找不到时直接返回。调用 `showDialog` 时传入单条轨道，设置 `barrierDismissible: true`，并在回调中调用 `confirmTrackLanguage`。对话框返回 warning 后仅在 `_canUsePlayer` 时显示 SnackBar。

- [ ] **步骤 3：增加“稍后确认”与可关闭语义**

给 `TrackLanguageConfirmationDialog` 增加 `TextButton`：

```dart
TextButton(
  onPressed: _saving ? null : () => Navigator.of(context).pop(),
  child: const Text('稍后确认'),
)
```

保留“保存并继续”，单轨保存后关闭。对话框不负责暂停、播放、切轨或退出播放器。

- [ ] **步骤 4：运行 widget 回归测试**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'; D:\flutter\bin\flutter.bat test test/track_language_confirmation_dialog_test.dart test/local_video_controller_test.dart
```

- [ ] **步骤 5：提交播放器交互修复**

```powershell
git add lib/pages/player/player_item.dart lib/pages/player/widgets/track_language_confirmation_dialog.dart test/track_language_confirmation_dialog_test.dart test/local_video_controller_test.dart
git commit -m "fix: 语言确认弹窗改为可关闭按需显示"
```

### 任务 5：版本、文档和完整验证

**文件：**
- 修改：`pubspec.yaml`
- 修改：`README.md`
- 修改：`UPDATE_DIALOG_COPY.md`
- 修改：`lib/core/app_version.dart`
- 修改：`test/version_consistency_test.dart`
- 修改：`tool/windows/build_signed_release.ps1`（仅在脚本内置版本断言需要同步时）
- 修改：`RELEASE_NOTES.md`
- 修改：`lib/utils/version_history.dart`

- [ ] **步骤 1：查询并记录当前安装版本**

运行 `Get-AppxPackage -Name com.kanyingyin.player`，将当前版本记录在交付日志中；未安装时明确记录未安装。

- [ ] **步骤 2：升级版本号**

将 `pubspec.yaml` 更新为 `2.1.43+20143`，MSIX 版本更新为 `2.1.43.0`，发布说明面向普通用户说明“字幕先正常显示，语言确认可稍后处理”。

- [ ] **步骤 3：重新生成 MobX 文件**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'; D:\flutter\bin\cache\dart-sdk\bin\dart.exe run build_runner build --delete-conflicting-outputs
```

- [ ] **步骤 4：运行完整质量门禁**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'; D:\flutter\bin\flutter.bat test
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'; D:\flutter\bin\flutter.bat analyze
```

预期：所有测试通过，`flutter analyze` 无错误。

- [ ] **步骤 5：构建并签名 MSIX**

先确认看影音进程已退出，再运行项目签名脚本：

```powershell
Get-Process -Name kanyingyin -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited }
& .\tool\windows\build_signed_release.ps1
```

核对清单版本为 `2.1.43.0`、签名为 `CN=KanYingYin`，最终文件必须复制到 `C:\Users\asus\Desktop\看影音-2.1.43.msix`，并生成同名异机安装 ZIP。

- [ ] **步骤 6：提交交付改动**

```powershell
git add pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart windows
git commit -m "发布 2.1.43 轨道语言确认优化"
```
