# 设置首页经典列表风格实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除关于页的 Kazumi 展示项，并将设置首页从卡片墙恢复为紧凑单列分组列表，同时保持入口、业务回调和全部操作动画不变。

**Architecture:** 保留 `SettingsHubContent` 的纯表现组件边界和 `onOpenPath` 路由回调，用现有 `KSettingsList`、`KSettingsSection`、`KSettingsTile` 替换首页专用卡片墙。删除失去调用方的 `SettingsHubCard`/`SettingsHubLayout`，不恢复 `card_settings_ui`，设置子页与 `SettingsMotion` 不做任何修改。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、Material 3、自有 KSettings 表现组件、flutter_test、Windows MSIX。

---

## 文件结构

- `lib/pages/my/my_page.dart`：设置首页入口分组、文案、图标及路由转发。
- `lib/pages/about/about_page.dart`：删除 Kazumi 展示项，保留许可证入口。
- `lib/features/settings/presentation/settings_presentation.dart`：移除已删除卡片组件的导出。
- `lib/features/settings/presentation/settings_hub_card.dart`：删除，仅服务于旧卡片墙。
- `test/settings_hub_page_test.dart`：验证首页使用分组列表、无卡片墙残留且路由完整。
- `test/settings_hub_layout_test.dart`：在 1280、900、640 像素宽度验证分组列表和路由转发。
- `test/settings_presentation_components_test.dart`：移除失效的卡片列数测试，保留动画和通用设置组件测试。
- `test/about_page_content_test.dart`：验证关于页无 Kazumi，README 仍保留来源说明。
- `pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`、`test/version_consistency_test.dart`：发布 2.1.39。

### Task 1: 用失败测试锁定经典分组列表和 Kazumi UI 零残留

**Files:**
- Modify: `test/settings_hub_page_test.dart`
- Modify: `test/settings_hub_layout_test.dart`
- Modify: `test/about_page_content_test.dart`

- [ ] **Step 1: 重写设置首页源码约束测试**

将 `test/settings_hub_page_test.dart` 的第一个测试改为：

```dart
test('设置主页恢复经典分组列表且保留全部入口', () {
  final source = File('lib/pages/my/my_page.dart').readAsStringSync();

  expect(source, contains('KSettingsList('));
  expect(source, contains('KSettingsSection('));
  expect(source, contains('KSettingsTile<void>.navigation('));
  expect(source, isNot(contains('SettingsHubCard(')));
  expect(source, isNot(contains('SettingsHubLayout.columnCountFor')));
  for (final section in <String>[
    '本地媒体库',
    '播放器设置',
    '应用与外观',
    '其他',
  ]) {
    expect(source, contains("'$section'"), reason: '缺少 $section 分组');
  }
  for (final label in <String>[
    'TMDB 刮削',
    '网盘数据源',
    '媒体识别',
    '播放设置',
    '操作设置',
    '外观设置',
    '界面设置',
    '关于',
  ]) {
    expect(source, contains("'$label'"), reason: '缺少 $label 入口');
  }
  for (final path in <String>[
    '/settings/tmdb',
    '/settings/cloud-sources',
    '/settings/media-recognition',
    '/settings/player',
    '/settings/keyboard',
    '/settings/theme',
    '/settings/interface',
    '/settings/about/',
  ]) {
    expect(source, contains("onOpenPath('$path')"));
  }
  expect(source, contains('Modular.to.pushNamed(path)'));
});
```

- [ ] **Step 2: 将真实布局测试改为分组列表断言**

保留 `pumpHub`，将第一个 Widget 测试改为：

```dart
testWidgets('设置分组列表在三种宽度下完整构建且无溢出', (tester) async {
  for (final width in <double>[1280, 900, 640]) {
    await pumpHub(tester, width: width);
    expect(find.byType(KSettingsSection), findsNWidgets(4));
    expect(find.byType(KSettingsNavigationTile), findsNWidgets(8));
    for (final section in <String>[
      '本地媒体库',
      '播放器设置',
      '应用与外观',
      '其他',
    ]) {
      expect(find.text(section), findsOneWidget);
    }
    expect(tester.takeException(), isNull, reason: '窗口宽度 $width');
  }
});
```

第二个测试只把名称改为“设置分组列表将入口路径原样转发”，点击和 `/settings/player` 断言保持原样。

- [ ] **Step 3: 重写关于页来源测试**

将 `README 和关于页面简单注明 Kazumi 来源` 改为：

```dart
test('README 保留来源说明但关于页面不展示 Kazumi', () {
  final readme = File('README.md').readAsStringSync();
  final about = File('lib/pages/about/about_page.dart').readAsStringSync();

  expect(
    readme,
    contains(
      '界面与操作参考 [Kazumi](https://github.com/Predidit/Kazumi)',
    ),
  );
  expect(about, isNot(contains('Kazumi')));
  expect(about, contains('开源许可与致谢'));
  expect(about, contains('开源许可证'));
});
```

- [ ] **Step 4: 运行测试并确认因旧 UI 而失败**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\settings_hub_page_test.dart test\settings_hub_layout_test.dart test\about_page_content_test.dart
```

Expected: FAIL；失败原因应为源码仍包含 `SettingsHubCard`、Widget 数量不是 4/8，且关于页仍包含 `Kazumi`。不能接受编译错误或测试环境错误作为 RED。

### Task 2: 最小实现经典单列设置首页

**Files:**
- Modify: `lib/pages/my/my_page.dart`
- Modify: `lib/pages/about/about_page.dart`
- Modify: `lib/features/settings/presentation/settings_presentation.dart`
- Delete: `lib/features/settings/presentation/settings_hub_card.dart`
- Modify: `test/settings_presentation_components_test.dart`

- [ ] **Step 1: 用分组列表替换 SettingsHubContent 的卡片网格**

将 `SettingsHubContent.build` 替换为以下实现：

```dart
@override
Widget build(BuildContext context) {
  final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
  Text text(String value) => Text(
        value,
        style: TextStyle(fontFamily: fontFamily),
      );

  return KSettingsList(
    maxWidth: 1000,
    sections: [
      KSettingsSection(
        title: text('本地媒体库'),
        tiles: [
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/tmdb'),
            leading: const Icon(Icons.movie_filter_outlined),
            title: text('TMDB 刮削'),
            description: text('配置中文标题、海报、简介与影片信息刮削'),
          ),
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/cloud-sources'),
            leading: const Icon(Icons.cloud_outlined),
            title: text('网盘数据源'),
            description: text('添加和管理 OpenList、夸克与百度网盘媒体来源'),
          ),
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/media-recognition'),
            leading: const Icon(Icons.video_file_outlined),
            title: text('媒体识别'),
            description: text('设置本地与网盘视频的识别大小限制'),
          ),
        ],
      ),
      KSettingsSection(
        title: text('播放器设置'),
        tiles: [
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/player'),
            leading: const Icon(Icons.display_settings_rounded),
            title: text('播放设置'),
            description: text('调整解码、渲染、字幕与播放行为'),
          ),
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/keyboard'),
            leading: const Icon(Icons.keyboard_rounded),
            title: text('操作设置'),
            description: text('管理播放器键盘快捷键与操作映射'),
          ),
        ],
      ),
      KSettingsSection(
        title: text('应用与外观'),
        tiles: [
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/theme'),
            leading: const Icon(Icons.palette_outlined),
            title: text('外观设置'),
            description: text('管理主题、字体、OLED 与屏幕刷新率'),
          ),
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/interface'),
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: text('界面设置'),
            description: text('设置启动页面与桌面界面行为'),
          ),
        ],
      ),
      KSettingsSection(
        title: text('其他'),
        tiles: [
          KSettingsTile<void>.navigation(
            onPressed: (_) => onOpenPath('/settings/about/'),
            leading: const Icon(Icons.info_outline_rounded),
            title: text('关于'),
            description: text('查看版本、许可、日志与缓存管理'),
          ),
        ],
      ),
    ],
  );
}
```

- [ ] **Step 2: 删除关于页 Kazumi 展示项**

从 `AboutPage` 的“开源许可与致谢”分组中删除以下完整 Widget：

```dart
KSettingsTile<void>(
  title: Text(
    '界面与操作参考 Kazumi',
    style: TextStyle(fontFamily: fontFamily),
  ),
),
```

保留紧随其后的 `KSettingsTile<void>.navigation` 开源许可证入口。

- [ ] **Step 3: 删除卡片墙表现组件残留**

删除 `lib/features/settings/presentation/settings_hub_card.dart`，并从 `settings_presentation.dart` 删除：

```dart
export 'settings_hub_card.dart';
```

从 `test/settings_presentation_components_test.dart` 删除整个“设置主页按窗口宽度切换三列两列和单列”测试。不要修改 `SettingsMotion` 或其余组件测试。

- [ ] **Step 4: 格式化本轮 Dart 文件**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\pages\my\my_page.dart lib\pages\about\about_page.dart lib\features\settings\presentation\settings_presentation.dart test\settings_hub_page_test.dart test\settings_hub_layout_test.dart test\settings_presentation_components_test.dart test\about_page_content_test.dart
```

Expected: 命令退出码 0。

- [ ] **Step 5: 运行目标测试并确认转绿**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\settings_hub_page_test.dart test\settings_hub_layout_test.dart test\settings_presentation_components_test.dart test\about_page_content_test.dart
```

Expected: 全部通过，1280/900/640 像素均无异常。

- [ ] **Step 6: 确认动画实现未被修改**

Run:

```powershell
git diff --exit-code HEAD -- lib\features\settings\presentation\settings_motion.dart lib\pages\settings\settings_module.dart lib\features\settings\presentation\k_settings_tile.dart
```

Expected: 无输出，退出码 0。

- [ ] **Step 7: 提交 UI 实现**

```powershell
git add lib\pages\my\my_page.dart lib\pages\about\about_page.dart lib\features\settings\presentation\settings_presentation.dart lib\features\settings\presentation\settings_hub_card.dart test\settings_hub_page_test.dart test\settings_hub_layout_test.dart test\settings_presentation_components_test.dart test\about_page_content_test.dart
git commit -m "恢复设置首页经典列表风格"
```

### Task 3: 发布 2.1.39

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 再次记录当前 Windows 已安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture
```

Expected: 记录当前安装版本；计划编写时实测为 `2.1.38.0 / X64`，不能依据 `pubspec.yaml` 替代该查询。

- [ ] **Step 2: 先更新版本一致性测试**

将 `test/version_consistency_test.dart` 中的常量改为：

```dart
const expectedVersion = '2.1.39';
const expectedBuildNumber = '20139';
```

- [ ] **Step 3: 运行版本测试并确认失败**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart
```

Expected: FAIL，实际版本仍为 `2.1.38`。

- [ ] **Step 4: 更新所有版本源**

执行以下精确更新：

```text
pubspec.yaml
version: 2.1.39+20139
msix_version: 2.1.39.0

lib/core/app_version.dart
static const String current = '2.1.39';

README.md
| 当前版本 | 2.1.39 |
```

在 `RELEASE_NOTES.md` 顶部加入：

```markdown
## 2.1.39+20139

MSIX 版本：2.1.39.0

### 更新弹窗文案

标题：看影音 2.1.39 测试版

- 设置主页恢复为紧凑的单列分组列表，媒体库、播放器、外观和其他入口更集中，原有路由与操作逻辑不变。
- 关于页面不再展示界面参考项，开源许可证入口和 README 来源说明继续保留。
- 设置项悬停、按下与页面前进返回动画保持不变，并继续遵循 Windows“减少动画”设置。
- 播放器退出卡死修复和本地与网盘经典海报墙继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变。
- 没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件。
```

将 `UPDATE_DIALOG_COPY.md` 的当前版本、标题和正文更新为：

```markdown
## 当前版本

- 应用版本：2.1.39
- 安装包版本：2.1.39.0
- 日期：2026-07-22

## 弹窗标题

看影音 2.1.39 测试版

## 弹窗正文

- 设置主页恢复为紧凑的单列分组列表，媒体库、播放器、外观和其他入口更集中，原有路由与操作逻辑不变。
- 关于页面不再展示界面参考项，开源许可证入口和 README 来源说明继续保留。
- 设置项悬停、按下与页面前进返回动画保持不变，并继续遵循 Windows“减少动画”设置。
- 播放器退出卡死修复和本地与网盘经典海报墙继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变。
- 没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件。
```

在 `versionHistoryList` 首位加入：

```dart
VersionHistory(
  version: '2.1.39',
  date: '2026-07-22',
  isPrerelease: true,
  changes: [
    '本测试版将设置主页恢复为紧凑的单列分组列表，媒体库、播放器、外观和其他入口更集中，原有路由与操作逻辑不变',
    '关于页面不再展示界面参考项，开源许可证入口和 README 来源说明继续保留',
    '设置项悬停、按下与页面前进返回动画保持不变，并继续遵循 Windows“减少动画”设置',
    '播放器退出卡死修复和本地与网盘经典海报墙继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变',
    '没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件',
  ],
),
```

- [ ] **Step 5: 格式化并运行版本一致性测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart
```

Expected: PASS。

- [ ] **Step 6: 提交版本更新**

```powershell
git add pubspec.yaml lib\core\app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib\utils\version_history.dart test\version_consistency_test.dart
git commit -m "发布 2.1.39 设置列表调整版"
```

### Task 4: 完整质量门禁

**Files:**
- Verify: all tracked Dart and project files

- [ ] **Step 1: 检查格式、残留和 diff**

Run:

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
rg -n "SettingsHubCard|SettingsHubLayout|界面与操作参考 Kazumi" lib test
git diff --check HEAD~2..HEAD
```

Expected: 格式命令退出码 0；`rg` 无匹配并以 1 退出；`git diff --check` 退出码 0。README 中的 Kazumi 来源说明不属于 UI 残留，不在本命令扫描范围内。

- [ ] **Step 2: 串行执行完整测试**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test
```

Expected: 全部测试通过，0 failure。不得与其他 Flutter/Pub 命令并行，避免 Git 依赖缓存竞态。

- [ ] **Step 3: 串行执行静态分析**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat analyze
```

Expected: `No issues found!`。

- [ ] **Step 4: 清理测试专用 APPDATA 并确认工作树干净**

解析 `D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata` 的绝对路径，确认它位于隔离工作树且末级目录名严格等于 `.dart_appdata` 后，用 `Remove-Item -LiteralPath ... -Recurse -Force` 删除。随后运行：

```powershell
git status --short
git -C D:\KanYingYin status --short
```

Expected: 两个命令均无输出。

### Task 5: 生成并验证签名交付包

**Files:**
- Build: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.39.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.39-异机安装包.zip`

- [ ] **Step 1: 确认看影音进程已退出**

Run:

```powershell
Get-Process -Name kanyingyin -ErrorAction SilentlyContinue
```

Expected: 无输出。若仍在运行，只报告并请求用户先退出，不强制结束用户进程。

- [ ] **Step 2: 生成 Windows Release、签名 MSIX 和异机安装包**

Run:

```powershell
& .\tool\windows\build_signed_release.ps1
```

Expected: Windows Release 构建成功、SignTool 验证 0 errors，并输出两个桌面路径和 SHA-256。

- [ ] **Step 3: 独立验证签名、清单、哈希和 ZIP 内容**

对桌面 MSIX 执行 `Get-AuthenticodeSignature`，并用 `System.IO.Compression.ZipFile` 读取 `AppxManifest.xml` 与异机 ZIP。必须同时满足：

```text
签名状态：Valid
签名者：CN=KanYingYin
证书指纹：A4A2CAA9623FBB8CD27ABC4838D186202EFC1AD6
Identity Name：com.kanyingyin.player
Version：2.1.39.0
ProcessorArchitecture：x64
构建目录 MSIX SHA-256 = 桌面 MSIX SHA-256 = ZIP 内 MSIX SHA-256
ZIP 固定包含：MSIX、看影音.cer、安装看影音.ps1、安装看影音.cmd、安装说明.txt、SHA256.txt
```

- [ ] **Step 4: 核对未自动安装和隔离状态**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture
git status --short
git -C D:\KanYingYin status --short
```

Expected: 已安装版本仍为构建前记录的 `2.1.38.0`，两个工作区均干净。保留 `codex/ui-refresh-v1` 分支和 `D:\KanYingYin\.worktrees\ui-refresh-v1`，不合并、不删除。
