# 设置中心 UI 重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将设置主页和全部设置子页重构为看影音自有的“档案馆控制中心”，保持所有操作逻辑不变，并加入已确认的影院氛围动效与顺滑页面转场。

**Architecture:** 在 `lib/features/settings/presentation/` 建立无业务依赖的设置表现层组件，以强类型回调承接现有页面逻辑。设置主页使用响应式功能卡网格，子页逐步替换 `card_settings_ui`；Flutter Modular 路由统一使用 260ms 水平淡入转场。页面仍拥有现有状态、存储与服务调用，公共组件只负责布局、语义和动画。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、Material 3、MobX/Provider、flutter_test、Windows MSIX。

---

### Task 1: 建立设置表现层组件与动效规范

**Files:**
- Create: `lib/features/settings/presentation/settings_motion.dart`
- Create: `lib/features/settings/presentation/k_settings_scaffold.dart`
- Create: `lib/features/settings/presentation/k_settings_section.dart`
- Create: `lib/features/settings/presentation/k_settings_tile.dart`
- Create: `lib/features/settings/presentation/settings_hub_card.dart`
- Create: `lib/features/settings/presentation/settings_presentation.dart`
- Create: `test/settings_presentation_components_test.dart`

- [ ] **Step 1: 编写失败的公共组件测试**

测试必须覆盖三种主页列数、导航回调、开关回调、强类型单选、禁用状态、键盘语义和减少动画：

```dart
test('设置主页按窗口宽度切换三列两列和单列', () {
  expect(SettingsHubLayout.columnCountFor(1280), 3);
  expect(SettingsHubLayout.columnCountFor(900), 2);
  expect(SettingsHubLayout.columnCountFor(640), 1);
});

testWidgets('设置开关和单选项保持强类型回调', (tester) async {
  bool? toggled;
  String? selected;
  await tester.pumpWidget(MaterialApp(home: KSettingsList(sections: [
    KSettingsSection(tiles: [
      KSettingsSwitchTile(title: const Text('开关'), value: false, onChanged: (v) => toggled = v),
      KSettingsRadioTile<String>(title: const Text('自动'), value: 'auto', groupValue: 'gpu', onChanged: (v) => selected = v),
    ]),
  ])));
  await tester.tap(find.text('开关'));
  await tester.tap(find.text('自动'));
  expect(toggled, isTrue);
  expect(selected, 'auto');
});
```

- [ ] **Step 2: 运行测试确认因组件不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\settings_presentation_components_test.dart`

Expected: FAIL，提示 `settings_presentation.dart` 或 `KSettingsTile` 不存在。

- [ ] **Step 3: 实现动效常量与减少动画策略**

```dart
abstract final class SettingsMotion {
  static const hoverDuration = Duration(milliseconds: 280);
  static const pressDuration = Duration(milliseconds: 90);
  static const pageDuration = Duration(milliseconds: 260);
  static const contentDuration = Duration(milliseconds: 220);
  static const stateDuration = Duration(milliseconds: 180);
  static const reducedDuration = Duration(milliseconds: 80);
  static const hoverCurve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration normal) {
    return MediaQuery.disableAnimationsOf(context) ? reducedDuration : normal;
  }
}
```

- [ ] **Step 4: 实现设置列表、分区和强类型设置项**

`KSettingsList` 使用居中的 `ListView`；`KSettingsSection` 使用 14px 圆角面板；导航、开关和单选分别使用独立强类型组件。核心接口固定为：

```dart
class KSettingsNavigationTile extends StatelessWidget {
  const KSettingsNavigationTile({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.value,
    this.enabled = true,
    required this.onPressed,
  });
  final Widget title;
  final Widget? description;
  final Widget? leading;
  final Widget? value;
  final bool enabled;
  final VoidCallback onPressed;
}

class KSettingsSwitchTile extends StatelessWidget {
  const KSettingsSwitchTile({
    super.key,
    required this.title,
    this.description,
    this.leading,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });
  final Widget title;
  final Widget? description;
  final Widget? leading;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
}
```

- [ ] **Step 5: 实现设置页面框架与主页功能卡**

`KSettingsScaffold` 统一 `SysAppBar`、920px 内容宽度和 220ms 内容淡入；`SettingsHubCard` 使用 280ms 悬停、90ms 按下和 `MediaQuery.disableAnimationsOf` 降级。主页网格断点固定为 1180/760px。

```dart
abstract final class SettingsHubLayout {
  static int columnCountFor(double width) {
    if (width >= 1180) return 3;
    if (width >= 760) return 2;
    return 1;
  }
}
```

- [ ] **Step 6: 运行组件测试并格式化**

Run: `D:\flutter\bin\dart.bat format lib\features\settings\presentation test\settings_presentation_components_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\settings_presentation_components_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交公共组件**

```powershell
git add lib/features/settings/presentation test/settings_presentation_components_test.dart
git commit -m "建立设置中心表现组件"
```

### Task 2: 重构设置主页与设置路由转场

**Files:**
- Modify: `lib/pages/my/my_page.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `test/navigation_config_test.dart`
- Create: `test/settings_hub_page_test.dart`

- [ ] **Step 1: 编写主页入口与响应式失败测试**

测试 `MyPage` 包含全部八个现有入口，标题仍为“设置”，且不再引用 `SettingsList`：

```dart
expect(find.text('TMDB 刮削'), findsOneWidget);
expect(find.text('网盘数据源'), findsOneWidget);
expect(find.text('媒体识别'), findsOneWidget);
expect(find.text('播放设置'), findsOneWidget);
expect(find.text('操作设置'), findsOneWidget);
expect(find.text('外观设置'), findsOneWidget);
expect(find.text('界面设置'), findsOneWidget);
expect(find.text('关于'), findsOneWidget);
```

源代码契约测试必须检查 `TransitionType.rightToLeftWithFade` 和 `SettingsMotion.pageDuration`。

- [ ] **Step 2: 运行测试确认旧主页与旧路由失败**

Run: `D:\flutter\bin\flutter.bat test test\settings_hub_page_test.dart test\navigation_config_test.dart`

Expected: FAIL，旧主页仍使用 `SettingsList`，路由未配置设置专用转场。

- [ ] **Step 3: 用控制中心主页替换旧列表**

保持 `PopScope`、`NavigationBarState` 和所有 `Modular.to.pushNamed` 路径原样，使用 `LayoutBuilder` 计算列数，并将所有入口映射为 `SettingsHubCard`。

- [ ] **Step 4: 为每条设置路由添加统一转场**

每个 `r.child` 使用：

```dart
transition: TransitionType.rightToLeftWithFade,
duration: SettingsMotion.pageDuration,
```

模块和依赖注入参数不变。

- [ ] **Step 5: 运行主页和路由测试**

Run: `D:\flutter\bin\flutter.bat test test\settings_hub_page_test.dart test\navigation_config_test.dart test\desktop_shell_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交主页与转场**

```powershell
git add lib/pages/my/my_page.dart lib/pages/settings/settings_module.dart test/settings_hub_page_test.dart test/navigation_config_test.dart
git commit -m "重构设置控制中心主页"
```

### Task 3: 迁移基础设置子页

**Files:**
- Modify: `lib/pages/settings/interface_settings.dart`
- Modify: `lib/pages/settings/renderer_settings.dart`
- Modify: `lib/pages/settings/super_resolution_settings.dart`
- Modify: `lib/pages/settings/displaymode_settings.dart`
- Modify: `lib/pages/settings/decoder_settings.dart`
- Modify: `lib/pages/settings/keyboard_settings.dart`
- Create: `test/settings_basic_pages_test.dart`

- [ ] **Step 1: 编写基础页面挂载与行为失败测试**

验证每页使用 `KSettingsScaffold`，并保持现有强类型值：界面启动页、渲染器字符串、显示模式对象、Anime4K 类型和键盘映射。

- [ ] **Step 2: 运行测试确认旧组件或旧布局失败**

Run: `D:\flutter\bin\flutter.bat test test\settings_basic_pages_test.dart test\interface_settings_content_test.dart test\local_only_settings_test.dart`

Expected: FAIL，页面尚未迁移至新组件。

- [ ] **Step 3: 逐页迁移到新框架**

将旧组件按以下规则替换，同时保留回调正文：

```dart
SettingsList       -> KSettingsList
SettingsSection    -> KSettingsSection
SettingsTile.navigation -> KSettingsNavigationTile
SettingsTile.switchTile -> KSettingsSwitchTile
SettingsTile.radioTile  -> KSettingsRadioTile<T>
```

`onPressed: (_) { ... }` 仅去掉未使用的 `BuildContext` 参数；`onToggle` 改为非空 `onChanged` 后不改变原来的值翻转与存储语句。

- [ ] **Step 4: 运行基础页面测试与相关回归**

Run: `D:\flutter\bin\flutter.bat test test\settings_basic_pages_test.dart test\interface_settings_content_test.dart test\local_only_settings_test.dart test\hardware_decoder_settings_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交基础页面迁移**

```powershell
git add lib/pages/settings/interface_settings.dart lib/pages/settings/renderer_settings.dart lib/pages/settings/super_resolution_settings.dart lib/pages/settings/displaymode_settings.dart lib/pages/settings/decoder_settings.dart lib/pages/settings/keyboard_settings.dart test/settings_basic_pages_test.dart
git commit -m "统一基础设置页面样式"
```

### Task 4: 迁移播放器和外观长页面

**Files:**
- Modify: `lib/pages/settings/player_settings.dart`
- Modify: `lib/pages/settings/theme_settings_page.dart`
- Modify: `test/app_theme_test.dart`
- Modify: `test/local_only_settings_test.dart`
- Modify: `test/log_settings_ui_test.dart`
- Create: `test/settings_long_pages_test.dart`

- [ ] **Step 1: 编写长页面分区和回调失败测试**

验证播放设置仍包含硬件解码、解码方式、渲染器、Anime4K、字幕、日志和诊断入口；外观设置仍包含模式、配色、动态颜色、系统字体、OLED、标题栏及刷新率。

- [ ] **Step 2: 运行测试确认旧组件失败**

Run: `D:\flutter\bin\flutter.bat test test\settings_long_pages_test.dart test\local_only_settings_test.dart test\log_settings_ui_test.dart test\app_theme_test.dart`

Expected: FAIL，页面仍使用旧设置组件。

- [ ] **Step 3: 按语义分区迁移播放设置**

分为“解码与渲染”“播放行为”“字幕与音频”“诊断与日志”，仅替换表现组件；所有 `setting.put`、平台判断、异步返回刷新及路由保持原样。

- [ ] **Step 4: 按语义分区迁移外观设置**

分为“主题”“显示”“桌面窗口”，保留 `MenuAnchor`、颜色选择对话框、动态配色、字体、OLED 和标题栏存储逻辑。

- [ ] **Step 5: 运行长页面和主题回归测试**

Run: `D:\flutter\bin\flutter.bat test test\settings_long_pages_test.dart test\local_only_settings_test.dart test\log_settings_ui_test.dart test\app_theme_test.dart test\app_widget_lifecycle_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交长页面迁移**

```powershell
git add lib/pages/settings/player_settings.dart lib/pages/settings/theme_settings_page.dart test/settings_long_pages_test.dart test/app_theme_test.dart test/local_only_settings_test.dart test/log_settings_ui_test.dart
git commit -m "重构播放与外观设置页面"
```

### Task 5: 迁移媒体、网盘与关于页面

**Files:**
- Modify: `lib/pages/settings/media_recognition_settings.dart`
- Modify: `lib/pages/settings/tmdb_settings.dart`
- Modify: `lib/pages/settings/cloud_sources_settings.dart`
- Modify: `lib/pages/cloud/openlist_source_editor.dart`
- Modify: `lib/pages/cloud/quark/quark_source_editor.dart`
- Modify: `lib/pages/cloud/quark/quark_share_import_page.dart`
- Modify: `lib/pages/cloud/baidu/baidu_source_editor.dart`
- Modify: `lib/pages/about/about_page.dart`
- Modify: `test/media_recognition_settings_ui_test.dart`
- Modify: `test/cloud_sources_ui_test.dart`
- Modify: `test/about_page_content_test.dart`
- Create: `test/settings_data_pages_test.dart`

- [ ] **Step 1: 编写数据页面与错误状态失败测试**

验证媒体识别值和扫描进度、TMDB 凭据状态、网盘空状态和新增来源、来源编辑表单、关于页许可/日志/缓存/版本入口均存在，且失败提示文本不变。

- [ ] **Step 2: 运行测试确认旧布局失败**

Run: `D:\flutter\bin\flutter.bat test test\settings_data_pages_test.dart test\media_recognition_settings_ui_test.dart test\cloud_sources_ui_test.dart test\about_page_content_test.dart`

Expected: FAIL，相关页面尚未统一到新设置组件。

- [ ] **Step 3: 迁移媒体识别与 TMDB 页面**

保留 `_showSizeChoices`、重新扫描回调、API Key 安全存储、连接检查和错误分类；进度状态用 `KSettingsTile` 及 `AnimatedSwitcher` 显示。

- [ ] **Step 4: 迁移网盘来源、选择器和编辑表单**

使用 `KSettingsScaffold`、统一分区和输入表面，保持来源类型、路由参数、凭据处理、目录选择、扫描、删除和导入逻辑不变。

- [ ] **Step 5: 迁移关于页面**

保留许可、默认关闭行为、日志、清缓存和版本显示逻辑，使用新分区与设置项组件。

- [ ] **Step 6: 运行数据页面及业务回归测试**

Run: `D:\flutter\bin\flutter.bat test test\settings_data_pages_test.dart test\media_recognition_settings_ui_test.dart test\cloud_sources_ui_test.dart test\about_page_content_test.dart test\tmdb_credential_manager_test.dart test\cloud_library_controller_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交数据页面迁移**

```powershell
git add lib/pages/settings lib/pages/cloud lib/pages/about/about_page.dart test/media_recognition_settings_ui_test.dart test/cloud_sources_ui_test.dart test/about_page_content_test.dart test/settings_data_pages_test.dart
git commit -m "统一媒体与网盘设置界面"
```

### Task 6: 移除旧 UI 依赖并完成可访问性回归

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `test/settings_ui_residue_test.dart`

- [ ] **Step 1: 编写旧 UI 零残留失败测试**

```dart
test('设置区域不再依赖 card_settings_ui', () {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  expect(pubspec, isNot(contains('card_settings_ui:')));
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    expect(entity.readAsStringSync(), isNot(contains('package:card_settings_ui/')));
  }
});
```

- [ ] **Step 2: 运行测试确认依赖仍存在**

Run: `D:\flutter\bin\flutter.bat test test\settings_ui_residue_test.dart`

Expected: FAIL，`pubspec.yaml` 与现有页面仍包含依赖时必须红灯。

- [ ] **Step 3: 删除依赖并刷新锁文件**

删除 `pubspec.yaml` 中的 `card_settings_ui`，运行：

Run: `D:\flutter\bin\flutter.bat pub get`

Expected: `pubspec.lock` 不再解析 `card_settings_ui`。

- [ ] **Step 4: 运行零残留、组件与页面测试**

Run: `D:\flutter\bin\flutter.bat test test\settings_ui_residue_test.dart test\settings_presentation_components_test.dart test\settings_hub_page_test.dart test\settings_basic_pages_test.dart test\settings_long_pages_test.dart test\settings_data_pages_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交依赖清理**

```powershell
git add pubspec.yaml pubspec.lock test/settings_ui_residue_test.dart
git commit -m "移除旧设置 UI 依赖"
```

### Task 7: 升级 2.1.38 并更新普通用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 查询并记录当前已安装版本**

Run: `Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,Architecture,PackageFullName`

Expected: 明确记录当前安装版本；未安装时记录“未安装”。

- [ ] **Step 2: 先把版本测试改为 2.1.38 并确认失败**

```dart
expect(pubspecVersion, '2.1.38+20138');
expect(msixVersion, '2.1.38.0');
expect(AppVersion.current, '2.1.38');
```

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart`

Expected: FAIL，生产版本仍为 2.1.37。

- [ ] **Step 3: 更新版本与发布文案**

设置 `version: 2.1.38+20138`、`msix_version: 2.1.38.0`，并说明设置中心重构、影院氛围动效、全部操作逻辑不变，以及播放器退出与经典海报墙修复继续保留。

- [ ] **Step 4: 运行版本与发布契约测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart test\signed_release_packaging_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交版本更新**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布 2.1.38 设置中心重构版"
```

### Task 8: 全量验证与签名交付

**Files:**
- Verify only: entire repository
- Output: `build/windows/x64/runner/Release/kanyingyin.msix`
- Output: `C:\Users\asus\Desktop\看影音-2.1.38.msix`
- Output: `C:\Users\asus\Desktop\看影音-2.1.38-异机安装包.zip`

- [ ] **Step 1: 运行格式、全量测试和静态分析**

Run: `D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .`

Run: `D:\flutter\bin\flutter.bat test`

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: 格式无改动、全部测试通过、静态分析无问题。

- [ ] **Step 2: 运行 Windows Release 与签名脚本**

Run: `powershell -ExecutionPolicy Bypass -File .\tool\windows\build_signed_release.ps1`

Expected: Release 构建成功，MSIX 签名验证 0 错误，并复制桌面安装包和异机包。

- [ ] **Step 3: 独立验证桌面产物**

检查：

```powershell
Get-AuthenticodeSignature 'C:\Users\asus\Desktop\看影音-2.1.38.msix'
Get-FileHash 'C:\Users\asus\Desktop\看影音-2.1.38.msix' -Algorithm SHA256
```

解压读取 `AppxManifest.xml`，确认 Name 为 `com.kanyingyin.player`、Version 为 `2.1.38.0`、ProcessorArchitecture 为 `x64`；构建目录和桌面 MSIX 哈希必须一致。

- [ ] **Step 4: 检查隔离状态与提交历史**

Run: `git status --short`

Run: `git -C D:\KanYingYin status --short`

Expected: 隔离工作树与主目录均无未提交修改；分支仍为 `codex/ui-refresh-v1`，未合并主分支。

- [ ] **Step 5: 保留隔离分支与工作树**

不安装、不合并、不删除工作树。报告桌面产物、签名、哈希、测试结果和回滚状态。
