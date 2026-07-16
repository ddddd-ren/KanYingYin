# Remove History And Private Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 彻底删除看影音的历史记录、跨会话播放进度、断点续播和隐身模式，清理旧历史数据，补充简短 Kazumi 归属说明，并以版本号不变的单一初始提交重新发布私密仓库。

**Architecture:** 删除历史领域层及所有调用方，使播放器只维护当前会话状态。新增一个独立、幂等的旧历史文件清理器，由 `GStorage.init()` 在打开其他 Hive box 前调用；清理失败只记录日志。最终使用最终提交的 Git tree 创建无父提交，避免把未提交的 `.learnings` 改动带入新仓库历史。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Hive CE、Flutter Test、Windows MSIX、GitHub REST API。

---

## File Structure

- `test/history_feature_removal_test.dart`：从用户可见入口、依赖注册、播放器写入和源码文件四个边界验证历史与隐身功能完全消失。
- `lib/utils/legacy_history_data_cleaner.dart`：只负责幂等删除旧 `histories.hive` 与 `histories.lock`。
- `test/legacy_history_data_cleaner_test.dart`：验证清理范围和幂等性。
- `lib/utils/storage.dart`：停止注册历史适配器和打开历史 box，启动时调用旧数据清理器。
- `lib/pages/player/player_item.dart`、`lib/pages/video/`、`lib/modules/video/local_playback_session.dart`：删除持久化历史写入与跨会话恢复参数，保留当前会话播放状态。
- `lib/pages/local/local_controller.dart`：删除基于历史记录推导继续观看集数的死代码。
- `lib/pages/my/my_page.dart`、`lib/pages/settings/`、`lib/pages/index_module.dart`：删除历史与隐身入口、路由和依赖注册。
- `README.md`、`lib/pages/about/about_page.dart`：移除历史功能宣称并简单注明 Kazumi 归属。
- 历史领域文件与相关测试文件：在引用清零后删除。

### Task 1: 建立历史功能零残留测试

**Files:**
- Create: `test/history_feature_removal_test.dart`
- Test: `test/history_feature_removal_test.dart`

- [ ] **Step 1: 写入失败的零残留测试**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('用户界面不再提供历史记录和隐身模式', () {
    final myPage = File('lib/pages/my/my_page.dart').readAsStringSync();
    final playerSettings =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();
    final settingsModule =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();

    expect(myPage, isNot(contains('历史记录')));
    expect(playerSettings, isNot(contains('privateMode')));
    expect(playerSettings, isNot(contains('隐身模式')));
    expect(settingsModule, isNot(contains('HistoryModule')));
    expect(settingsModule, isNot(contains('"/history"')));
  });

  test('运行时不再注册或写入观看历史', () {
    final indexModule =
        File('lib/pages/index_module.dart').readAsStringSync();
    final playerItem =
        File('lib/pages/player/player_item.dart').readAsStringSync();
    final storage = File('lib/utils/storage.dart').readAsStringSync();

    for (final text in [
      'HistoryController',
      'IHistoryRepository',
      'HistoryRepository',
      'updateHistory(',
      'historySource',
      'HistorySourceType',
    ]) {
      expect('$indexModule\n$playerItem', isNot(contains(text)));
    }
    expect(storage, isNot(contains('Box<History>')));
    expect(storage, isNot(contains('HistoryAdapter')));
    expect(storage, isNot(contains('ProgressAdapter')));
    expect(storage, isNot(contains("privateMode = 'privateMode'")));
  });

  test('历史领域源码已删除', () {
    for (final path in [
      'lib/modules/history/history_module.dart',
      'lib/modules/history/history_module.g.dart',
      'lib/repositories/history_repository.dart',
      'lib/pages/history/history_controller.dart',
      'lib/pages/history/history_controller.g.dart',
      'lib/pages/history/history_module.dart',
      'lib/pages/history/history_page.dart',
      'lib/bean/card/bangumi_history_card.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });
}
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\history_feature_removal_test.dart --reporter expanded`

Expected: FAIL，失败信息指出当前仍包含“历史记录”、`privateMode`、历史注册和历史领域文件。

- [ ] **Step 3: 提交失败测试**

```powershell
git add -- test/history_feature_removal_test.dart
git commit -m "test: 定义历史功能删除边界"
```

### Task 2: 清理旧历史数据并移除 Hive 历史初始化

**Files:**
- Create: `lib/utils/legacy_history_data_cleaner.dart`
- Create: `test/legacy_history_data_cleaner_test.dart`
- Modify: `lib/utils/storage.dart`

- [ ] **Step 1: 写入旧数据清理器失败测试**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/legacy_history_data_cleaner.dart';

void main() {
  test('只删除旧历史文件且重复执行安全', () async {
    final directory =
        await Directory.systemTemp.createTemp('legacy_history_cleanup_');
    addTearDown(() => directory.delete(recursive: true));
    final history = File('${directory.path}/histories.hive');
    final lock = File('${directory.path}/histories.lock');
    final setting = File('${directory.path}/setting.hive');
    final media = File('${directory.path}/movie.mkv');
    await history.writeAsString('history');
    await lock.writeAsString('lock');
    await setting.writeAsString('setting');
    await media.writeAsString('video');

    await LegacyHistoryDataCleaner.deleteFrom(directory);
    await LegacyHistoryDataCleaner.deleteFrom(directory);

    expect(await history.exists(), isFalse);
    expect(await lock.exists(), isFalse);
    expect(await setting.exists(), isTrue);
    expect(await media.exists(), isTrue);
  });
}
```

- [ ] **Step 2: 运行测试并确认缺少清理器而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\legacy_history_data_cleaner_test.dart --reporter expanded`

Expected: FAIL，提示 `legacy_history_data_cleaner.dart` 或 `LegacyHistoryDataCleaner` 不存在。

- [ ] **Step 3: 实现最小旧数据清理器**

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

class LegacyHistoryDataCleaner {
  const LegacyHistoryDataCleaner._();

  static Future<void> deleteFrom(Directory directory) async {
    for (final name in const ['histories.hive', 'histories.lock']) {
      final file = File(p.join(directory.path, name));
      if (await file.exists()) await file.delete();
    }
  }
}
```

- [ ] **Step 4: 将清理器接入存储初始化并移除历史 box**

在 `GStorage.init()` 计算 `_hivePath` 后、打开 `setting` 前执行：

```dart
try {
  await LegacyHistoryDataCleaner.deleteFrom(Directory(_hivePath!));
} catch (error, stackTrace) {
  AppLogger().w(
    'GStorage: failed to delete legacy history data',
    error: error,
    stackTrace: stackTrace,
  );
}
```

同时删除 `Box<History> histories`、历史模型 import、`HistoryAdapter`/`ProgressAdapter` 注册和 `histories` box 打开逻辑；保留 `setting` 与其他存储不变。

- [ ] **Step 5: 运行清理器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\legacy_history_data_cleaner_test.dart --reporter expanded`

Expected: PASS，1 test passed。

- [ ] **Step 6: 提交旧数据清理**

```powershell
git add -- lib/utils/legacy_history_data_cleaner.dart lib/utils/storage.dart test/legacy_history_data_cleaner_test.dart
git commit -m "refactor: 清理旧观看历史数据"
```

### Task 3: 删除播放器历史写入与跨会话恢复

**Files:**
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/video/video_page_controller_interface.dart`
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/modules/video/local_playback_session.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `test/local_video_controller_test.dart`
- Modify: `test/cloud_playback_resolver_test.dart`
- Delete: `test/cloud_history_availability_test.dart`

- [ ] **Step 1: 先修改播放测试表达删除后的行为**

在 `test/local_video_controller_test.dart` 删除传入 `resumePositionSeconds` 的旧测试，新增：

```dart
test('重新打开本地视频始终从开头播放', () {
  final controller = LocalVideoController();
  controller.openFilePlayback(
    filePath: r'D:\Video\01.mkv',
    seriesTitle: '测试动画',
    autoLoadSubtitle: false,
  );

  expect(controller.createPlaybackParams().offset, 0);
});
```

在 `test/cloud_playback_resolver_test.dart` 删除 `historySource`、`cloudHistoryIdentity`、`parseCloudHistoryIdentity` 和“云播放历史”断言；保留并继续执行“刷新事务保留暂停态和进度”测试。

- [ ] **Step 2: 运行定向测试并确认旧 API 仍存在导致负向测试失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\history_feature_removal_test.dart test\local_video_controller_test.dart test\cloud_playback_resolver_test.dart --reporter expanded`

Expected: FAIL，零残留测试仍检测到播放器历史写入和 `historySource`。

- [ ] **Step 3: 删除播放器历史写入**

从 `player_item.dart` 删除 `HistoryController`、`HistorySourceType` imports、`historyController` 字段，以及定时器中的整个“历史记录相关”块。保留定时器里的位置同步、音量、亮度和自动连播代码。

- [ ] **Step 4: 删除跨会话恢复 API**

从 `IVideoPageController` 删除 `historySource`。从 `LocalPlaybackSession` 删除 `resumePositionSeconds` 字段、构造参数和 `selectEpisode()` 传递。

从 `LocalVideoController` 删除 `_cloudResumePositionSeconds`、`resumePositionSeconds`、`historySource`、`openCloudPlayback()` 与 `openFilePlayback()` 的恢复参数。构建本地与首次网盘 `PlaybackInitParams` 时使用 `offset: 0`。保留 `changeEpisode(..., offset:)` 和 `CloudPlaybackRefreshTransaction`，因为它们只维护当前会话状态。

从 `video_page.dart` 删除首次初始化时读取 `localVideoController.resumePositionSeconds`，首次播放使用默认 `offset: 0`。

从 `cloud_playback_resolver.dart` 删除仅供持久化历史使用的 `cloudHistoryIdentity()`、`CloudHistoryIdentity` 和 `parseCloudHistoryIdentity()`；保留链接解析、刷新保护和当前会话刷新事务。

- [ ] **Step 5: 删除本地媒体库历史辅助逻辑**

从 `LocalController` 构造函数、私有构造函数和字段中删除 `IHistoryRepository`。删除 `getLocalPlaybackProgress()`、`continueEpisodeForSeries()`、`nextEpisodeForSeries()`、`_localHistories()`、`_episodeIndexInHistory()` 与 `LocalPlaybackProgress`，并删除历史 import。

- [ ] **Step 6: 运行播放器定向测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_video_controller_test.dart test\cloud_playback_resolver_test.dart test\local_controller_test.dart --reporter expanded`

Expected: PASS；首次播放 offset 为 0，云链接刷新事务仍将当前会话位置合并到新参数。

- [ ] **Step 7: 提交播放器链路删除**

```powershell
git add -- lib/pages/player/player_item.dart lib/pages/video/video_page_controller_interface.dart lib/pages/video/local_video_controller.dart lib/pages/video/video_page.dart lib/modules/video/local_playback_session.dart lib/pages/local/local_controller.dart lib/services/cloud/cloud_playback_resolver.dart test/local_video_controller_test.dart test/cloud_playback_resolver_test.dart test/cloud_history_availability_test.dart
git commit -m "refactor: 删除播放历史与断点续播"
```

### Task 4: 删除历史领域、界面、路由与隐身模式

**Files:**
- Modify: `lib/pages/my/my_page.dart`
- Modify: `lib/pages/settings/player_settings.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `lib/utils/storage.dart`
- Modify: `test/local_only_settings_test.dart`
- Delete: `lib/modules/history/history_module.dart`
- Delete: `lib/modules/history/history_module.g.dart`
- Delete: `lib/repositories/history_repository.dart`
- Delete: `lib/pages/history/history_controller.dart`
- Delete: `lib/pages/history/history_controller.g.dart`
- Delete: `lib/pages/history/history_module.dart`
- Delete: `lib/pages/history/history_page.dart`
- Delete: `lib/bean/card/bangumi_history_card.dart`
- Delete: `test/history_module_test.dart`

- [ ] **Step 1: 删除用户入口和隐身设置**

从 `my_page.dart` 删除“历史记录” `SettingsTile`。从 `player_settings.dart` 删除 `privateMode` 字段、初始化读取和“隐身模式”开关。从 `SettingBoxKey` 删除 `privateMode`。

- [ ] **Step 2: 删除路由与依赖注册**

从 `settings_module.dart` 删除 `HistoryModule` import 和 `/history` 模块路由。从 `index_module.dart` 删除历史仓库、控制器 imports，以及 `IHistoryRepository`、`HistoryController` 单例注册。

- [ ] **Step 3: 删除历史领域文件和旧测试**

删除文件清单中列出的历史模型、生成适配器、仓库、页面、控制器、卡片和 `history_module_test.dart`。不要运行代码生成，因为这些生成文件所属类型已整体删除。

- [ ] **Step 4: 加强现有设置负向测试**

在 `test/local_only_settings_test.dart` 增加：

```dart
test('设置页不再提供历史记录和隐身模式', () {
  final myPage = File('lib/pages/my/my_page.dart').readAsStringSync();
  final playerSettings =
      File('lib/pages/settings/player_settings.dart').readAsStringSync();
  expect(myPage, isNot(contains('历史记录')));
  expect(playerSettings, isNot(contains('隐身模式')));
  expect(playerSettings, isNot(contains('privateMode')));
});
```

- [ ] **Step 5: 运行零残留与设置测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\history_feature_removal_test.dart test\local_only_settings_test.dart --reporter expanded`

Expected: PASS。

- [ ] **Step 6: 全仓搜索历史运行时引用**

Run: `rg -n --glob '*.dart' "HistoryController|IHistoryRepository|HistoryRepository|HistorySourceType|privateMode|historySource|resumePositionSeconds" lib test`

Expected: 无输出。历史版本说明中的自然语言不属于运行时引用。

- [ ] **Step 7: 提交界面与领域删除**

```powershell
git add -- lib/pages/my/my_page.dart lib/pages/settings/player_settings.dart lib/pages/settings/settings_module.dart lib/pages/index_module.dart lib/utils/storage.dart lib/modules/history lib/repositories/history_repository.dart lib/pages/history lib/bean/card/bangumi_history_card.dart test/history_module_test.dart test/history_feature_removal_test.dart test/local_only_settings_test.dart
git commit -m "refactor: 移除历史记录和隐身模式"
```

### Task 5: 更新用户文案与 Kazumi 归属

**Files:**
- Modify: `README.md`
- Modify: `lib/pages/about/about_page.dart`
- Modify: `test/about_page_content_test.dart`
- Modify: `test/version_consistency_test.dart`

- [ ] **Step 1: 先写 Kazumi 归属失败测试**

在 `test/about_page_content_test.dart` 增加：

```dart
test('README 和关于页面简单注明 Kazumi 来源', () {
  final readme = File('README.md').readAsStringSync();
  final about = File('lib/pages/about/about_page.dart').readAsStringSync();
  expect(readme, contains('界面与操作参考 [Kazumi](https://github.com/Predidit/Kazumi)'));
  expect(about, contains('界面与操作参考 Kazumi'));
});
```

- [ ] **Step 2: 运行测试并确认缺少说明而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\about_page_content_test.dart --reporter expanded`

Expected: FAIL，README 和关于页面尚无 Kazumi 说明。

- [ ] **Step 3: 更新 README 当前功能说明**

删除“保存播放历史、观看进度和最近播放位置”“隐身模式下不记录观看历史”，并将数据目录说明中的“播放历史”删除。在“开源来源与致谢”列表首项加入：

```markdown
- 界面与操作参考 [Kazumi](https://github.com/Predidit/Kazumi)。
```

版本表继续保持 `1.0.0`，不得修改 `pubspec.yaml`、`msix_version` 或 `ApiEndpoints.version`。

- [ ] **Step 4: 在关于页面加入静态简短说明**

在关于页许可证区域加入不触发外部导航的普通 `SettingsTile`：

```dart
SettingsTile(
  title: Text(
    '界面与操作参考 Kazumi',
    style: TextStyle(fontFamily: fontFamily),
  ),
),
```

- [ ] **Step 5: 调整版本一致性测试**

保持预期版本 `1.0.0+10000` 不变，删除对当前 README 包含“播放历史”的任何要求，并增加 Kazumi 说明断言。

- [ ] **Step 6: 运行文案测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\about_page_content_test.dart test\version_consistency_test.dart --reporter expanded`

Expected: PASS。

- [ ] **Step 7: 提交用户文案**

```powershell
git add -- README.md lib/pages/about/about_page.dart test/about_page_content_test.dart test/version_consistency_test.dart
git commit -m "docs: 说明 Kazumi 界面与操作来源"
```

### Task 6: 完整验证与正式安装包

**Files:**
- Verify: entire project
- Output: `build/windows/x64/runner/Release/kanyingyin.msix`
- Output: `C:\Users\asus\Desktop\看影音-1.0.0.msix`

- [ ] **Step 1: 格式化本轮 Dart 文件**

Run: `D:\flutter\bin\dart.bat format lib test`

Expected: exit 0。

- [ ] **Step 2: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub --reporter compact`

Expected: All tests passed。

- [ ] **Step 3: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 4: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit 0，`kanyingyin.exe` 与 `data/app.so` 为本轮时间。

- [ ] **Step 5: 使用 DPAPI 密码生成 MSIX**

从 `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml` 读取 `SecureString`，转换后仅存于当前 PowerShell 变量，并执行：

```powershell
D:\flutter\bin\cache\dart-sdk\bin\dart.exe run msix:create --build-windows false --certificate-password $password
```

Expected: `build\windows\x64\runner\Release\kanyingyin.msix` 创建成功。

- [ ] **Step 6: 验证并复制桌面安装包**

读取 MSIX 中 `AppxManifest.xml` 并验证：

```text
Identity.Name=com.kanyingyin.player
Identity.Version=1.0.0.0
DisplayName=看影音
Signature=Valid
```

复制为 `C:\Users\asus\Desktop\看影音-1.0.0.msix`，记录文件大小和 SHA-256。

### Task 7: 重建单一初始提交并重新发布私密仓库

**Files:**
- Git tree: final committed project state
- GitHub repository: `ddddd-ren/KanYingYin`
- GitHub Release: `v1.0`

- [ ] **Step 1: 审查最终状态并提交所有本轮文件**

Run: `git status --short`、`git diff --check`、`git diff --stat`。

只暂存本轮相关文件；确认 `.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md` 仍未暂存。创建最终实现提交后重新运行完整验证，不使用未提交树构建根提交。

- [ ] **Step 2: 删除旧 GitHub Release**

通过 Git Credential Manager `get --no-ui` 取得当前 GitHub 凭据，并调用：

```text
DELETE https://api.github.com/repos/ddddd-ren/KanYingYin/releases/{release_id}
```

Expected: HTTP 204。仓库可见性必须仍为 `private`。

- [ ] **Step 3: 从最终 tree 创建无父提交**

```powershell
$tree = git rev-parse 'HEAD^{tree}'
$rootCommit = '看影音 v1.0 正式版' | git commit-tree $tree
git switch -c codex/clean-v1 $rootCommit
git branch -M main
git tag -f -a v1.0 -m '看影音 v1.0 正式版' $rootCommit
```

Expected: `git rev-list --count main` 输出 `1`；工作区仍只显示用户原有 `.learnings` 未提交修改。

- [ ] **Step 4: 强制替换远端 main 与 v1.0**

本次命令设置 `GIT_CONFIG_GLOBAL=NUL`，避免全局 `ghfast.top`/`gitclone.com` URL 重写：

```powershell
git push --force --set-upstream origin main
git push --force origin refs/tags/v1.0
```

Expected: 远端 `main` 和 `v1.0` 均指向新根提交。不要推送其他本地分支或 `v2.0.7` 标签。

- [ ] **Step 5: 重新创建正式 Release 并上传 MSIX**

通过 GitHub REST API 创建 `draft=false`、`prerelease=false`、`tag_name=v1.0` 的 Release。正文说明本地媒体正式功能、网盘挂载仍未完全实现，不再宣称历史记录、断点续播或隐身模式。上传资产名 `KanYingYin-1.0.0.msix`，标签为“看影音 v1.0 Windows 安装包”。

- [ ] **Step 6: 最终只读核验**

通过 GitHub API 验证：

```text
repository.private=true
branches=[main]
tags=[v1.0]
main commit count=1
release.draft=false
release.prerelease=false
asset.state=uploaded
asset.size=桌面 MSIX 大小
```

同时复核远端 root commit、MSIX 清单版本、签名和 SHA-256。
