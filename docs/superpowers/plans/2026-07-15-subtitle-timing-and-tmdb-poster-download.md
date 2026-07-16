# 字幕时间偏移与 TMDB 海报下载实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加按视频记忆的字幕时间偏移，并在 TMDB 刮削成功后把海报保存到每个视频目录的 `tmdb-poster.jpg`。

**Architecture:** 字幕偏移由 `PlayerController` 负责加载、限制、同步 MPV 和持久化，字幕设置面板只调用控制器动作。TMDB 刮削服务通过注入的海报下载接口统一处理自动匹配和手动候选，按目录去重下载并更新媒体索引；页面根据扩展后的结果显示部分失败提示。

**Tech Stack:** Flutter、Dart、MobX、media_kit/MPV、Hive、Dio、flutter_test

---

## 文件结构

- 修改 `lib/pages/player/player_controller.dart`：字幕偏移状态、按视频读写和 MPV 同步。
- 修改 `lib/pages/player/widgets/subtitle_settings_overlay.dart`：字幕时间滑块、前后调节和重置。
- 修改 `lib/utils/storage.dart`：字幕偏移映射存储键。
- 修改生成文件 `lib/pages/player/player_controller.g.dart`：由 build_runner 更新 MobX 代码。
- 修改 `lib/services/tmdb/local_tmdb_scrape_service.dart`：下载协调、目录去重、结果统计和索引封面更新。
- 修改 `lib/services/poster_service.dart`：允许覆盖旧 `tmdb-poster.jpg` 的明确目标下载。
- 修改 `lib/services/local_cover_finder.dart`：优先识别 `tmdb-poster`。
- 修改 `lib/services/tmdb/tmdb_scraper.dart`：刮削结果携带海报下载失败数量。
- 修改 `lib/pages/local/local_page.dart`、`lib/pages/local/library_sheet.dart`：部分下载失败提示。
- 修改相关测试：覆盖字幕偏移、海报下载、封面优先级和页面控件。
- 修改版本与发布说明文件：统一发布一个新版本。

### Task 1: 按视频保存字幕时间偏移

**Files:**
- Modify: `lib/utils/storage.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_controller.g.dart`
- Test: `test/player_controller_subtitle_test.dart`

- [ ] **Step 1: 写失败测试**

创建控制器测试，使用两个本地视频路径，断言新视频默认偏移为 `0.0`，设置 `-2.5` 后重新初始化同一路径可恢复，另一路径仍为 `0.0`；同时断言输入 `31` 和 `-31` 被限制为 `30` 和 `-30`，重置后恢复零值。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\player_controller_subtitle_test.dart
```

预期：因 `subtitleDelaySeconds`、`setSubtitleDelay` 和 `resetSubtitleDelay` 尚不存在而失败。

- [ ] **Step 3: 实现最小字幕偏移状态**

在 `SettingBoxKey` 增加 `subtitleDelayByVideo`。在 `PlayerController` 增加可观察的 `double subtitleDelaySeconds = 0.0`，以规范化的 `videoUrl` 为键读取 `Map<String, dynamic>`；实现：

```dart
@action
Future<void> setSubtitleDelay(double seconds) async {
  subtitleDelaySeconds = (seconds * 2).round() / 2;
  subtitleDelaySeconds = subtitleDelaySeconds.clamp(-30.0, 30.0);
  await _syncSubtitleDelayToPlayer();
  await _saveSubtitleDelayForCurrentVideo();
}

@action
Future<void> resetSubtitleDelay() => setSubtitleDelay(0.0);
```

在载入新媒体时读取当前视频记录，在播放器初始化完成后调用 `NativePlayer.setProperty('sub-delay', value)`。零值从映射中移除；存储异常回退为零并记录日志。

- [ ] **Step 4: 生成 MobX 代码并验证测试**

```powershell
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' run build_runner build --delete-conflicting-outputs
& 'D:\flutter\bin\flutter.bat' test test\player_controller_subtitle_test.dart
```

预期：字幕偏移测试通过。

- [ ] **Step 5: 提交字幕状态实现**

```powershell
git add lib/utils/storage.dart lib/pages/player/player_controller.dart lib/pages/player/player_controller.g.dart test/player_controller_subtitle_test.dart
git commit -m "feat: 按视频记忆字幕时间偏移"
```

### Task 2: 增加字幕时间调节界面

**Files:**
- Modify: `lib/pages/player/widgets/subtitle_settings_overlay.dart`
- Test: `test/local_video_controller_test.dart`

- [ ] **Step 1: 写失败测试**

增加界面结构回归测试，断言字幕设置包含“字幕时间”、“提前 0.5 秒”、“延后 0.5 秒”、“重置”，滑块范围为 `-30` 到 `30`、分段数为 `120`，并调用控制器的字幕偏移动作。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\local_video_controller_test.dart --plain-name "字幕设置支持按视频调节出现时间"
```

预期：界面尚无字幕时间控件而失败。

- [ ] **Step 3: 实现字幕时间区域**

在样式设置前加入 `_buildTimingControls`。使用现有 `_SubtitleSlider`，范围 `-30.0` 至 `30.0`、`divisions: 120`；两个 `IconButton` 分别调用当前值减/加 `0.5`，重置按钮调用 `resetSubtitleDelay`。数值文案负值显示“提前 X 秒”，正值显示“延后 X 秒”，零值显示“同步”。

- [ ] **Step 4: 运行界面测试**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\local_video_controller_test.dart
```

预期：全部通过。

- [ ] **Step 5: 提交字幕界面**

```powershell
git add lib/pages/player/widgets/subtitle_settings_overlay.dart test/local_video_controller_test.dart
git commit -m "feat: 增加字幕时间调节控件"
```

### Task 3: 下载并优先识别 TMDB 本地海报

**Files:**
- Modify: `lib/services/poster_service.dart`
- Modify: `lib/services/local_cover_finder.dart`
- Modify: `lib/services/tmdb/tmdb_scraper.dart`
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`
- Test: `test/local_tmdb_integration_test.dart`
- Test: `test/local_media_scanner_test.dart`

- [ ] **Step 1: 写失败测试**

在 TMDB 集成测试中构造同系列三个索引项，其中两个位于同一目录、一个位于另一目录；注入假下载器后断言只下载两次，目标均为 `tmdb-poster.jpg`，索引 cover 更新为各自目录文件。增加部分失败用例，断言元数据仍保存且结果的失败数为 `1`。增加封面查找测试，断言 `tmdb-poster.jpg` 优先于已有 `cover.jpg`。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\local_tmdb_integration_test.dart test\local_media_scanner_test.dart
```

预期：刮削服务没有下载器与失败统计，封面查找器不识别优先名称，测试失败。

- [ ] **Step 3: 扩展明确目标下载**

为 `PosterService.downloadPosterTo` 增加 `bool overwrite = false`；当 `overwrite` 为真时写入临时文件并替换目标，避免失败时破坏旧 `tmdb-poster.jpg`。定义可注入的下载回调类型供测试使用。

- [ ] **Step 4: 实现刮削后目录去重下载**

`LocalTmdbScrapeService` 接收下载回调。匹配元数据存在且 `posterUrl` 非空时，将 TMDB 路径补成 `https://image.tmdb.org/t/p/w780...`，按 `path.dirname(item.path)` 去重，下载到 `path.join(directory, 'tmdb-poster.jpg')`。成功目录内的所有索引项使用 `copyWith(cover: savedPath)` 更新；失败只累计 `posterDownloadFailures`，不撤销 TMDB 元数据。

- [ ] **Step 5: 统一自动与手动候选流程**

自动匹配在元数据写入后调用同一私有下载方法；`selectCandidate` 返回包含 metadata 和下载统计的结果类型，使手动候选也走相同流程。保留 API Key 为空和无索引项的既有行为。

- [ ] **Step 6: 调整本地封面优先级**

在 `LocalCoverFinder.findVideoCover` 和 `findDirCover` 的第一步查找 `tmdb-poster`，扩展名继续使用既有集合，不改变其他封面文件。

- [ ] **Step 7: 运行 TMDB 和扫描测试**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\local_tmdb_integration_test.dart test\local_media_scanner_test.dart
```

预期：多目录、去重、部分失败、手动候选和优先级测试全部通过。

- [ ] **Step 8: 提交海报下载实现**

```powershell
git add lib/services/poster_service.dart lib/services/local_cover_finder.dart lib/services/tmdb/tmdb_scraper.dart lib/services/tmdb/local_tmdb_scrape_service.dart test/local_tmdb_integration_test.dart test/local_media_scanner_test.dart
git commit -m "feat: TMDB 刮削后下载本地海报"
```

### Task 4: 页面反馈与即时刷新

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Modify: `test/local_video_controller_test.dart`

- [ ] **Step 1: 写失败测试**

增加回归测试，断言单部刮削和媒体库入口在 `posterDownloadFailures > 0` 时显示“TMDB 信息已更新，部分封面下载失败”，并确认控制器完成下载后重新加载本地索引。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\local_video_controller_test.dart
```

预期：页面没有部分失败提示而失败。

- [ ] **Step 3: 实现结果透传和提示**

控制器让自动匹配和手动候选返回统一结果并在完成后同步重新加载索引。两个页面根据失败数选择提示文案；成功下载时保留现有提示，匹配失败和 API Key 缺失文案不变。

- [ ] **Step 4: 运行页面测试并提交**

```powershell
& 'D:\flutter\bin\flutter.bat' test test\local_video_controller_test.dart test\local_tmdb_integration_test.dart
git add lib/pages/local/local_controller.dart lib/pages/local/local_page.dart lib/pages/local/library_sheet.dart test/local_video_controller_test.dart
git commit -m "feat: 显示 TMDB 海报下载结果"
```

### Task 5: 版本、完整验证与安装包

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 升级统一版本并更新用户文案**

从 `1.2.7+10207` 升级到 `1.3.0+10300`，MSIX 使用 `1.3.0.0`。更新日志说明“字幕时间可按视频调整并记忆”和“TMDB 海报自动保存到视频文件夹，可离线显示”。

- [ ] **Step 2: 运行完整质量检查**

```powershell
& 'D:\flutter\bin\flutter.bat' test
& 'D:\flutter\bin\flutter.bat' analyze
git diff --check
```

预期：全部测试通过，静态分析无问题，diff 无空白错误。

- [ ] **Step 3: 构建 Windows Release 和 MSIX**

按 `kanyingyin-msix-packaging` skill 执行：

```powershell
& 'D:\flutter\bin\flutter.bat' build windows --release --no-pub
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' run msix:create --build-windows false
```

确认 `kanyingyin.exe` 和 `data/app.so` 时间戳为本轮构建，清单版本为 `1.3.0.0`，数字签名有效。

- [ ] **Step 4: 复制桌面安装包并校验**

复制为 `C:\Users\asus\Desktop\看影音-1.3.0.msix`，确认源包与桌面包 SHA-256 一致并记录文件大小。

- [ ] **Step 5: 提交发布版本**

```powershell
git add pubspec.yaml lib/request/config/api_endpoints.dart RELEASE_NOTES.md lib/utils/version_history.dart
git commit -m "release: 发布看影音 1.3.0"
git status --short
```

预期：工作区干净。
