# Desktop media library UI refresh implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an isolated, rollback-friendly Windows UI refresh that gives 看影音 its own desktop media-library identity without changing player behavior or user media data.

**Architecture:** Add a focused application-theme factory and a width-driven desktop shell, then adapt the shared media presentation components so local and cloud pages inherit the same visual language. Keep controllers, repositories, routes, player widgets, and persistence formats unchanged.

**Tech Stack:** Flutter 3.41.9, Material 3, Flutter Modular, Provider, MobX, flutter_test, Windows MSIX

---

### Task 1: Create the branded theme boundary

**Files:**
- Create: `lib/theme/app_theme.dart`
- Modify: `lib/app_widget.dart`
- Modify: `lib/pages/settings/theme_settings_page.dart`
- Test: `test/app_theme_test.dart`

- [ ] **Step 1: Write the failing theme tests**

Create tests that call `AppTheme.light()` and `AppTheme.dark()` and assert the fixed brand values, neutral scaffold surfaces, 8 px card radius, 12 px dialog radius, and retained MiSans font family.

```dart
test('默认深色主题使用银幕档案馆配色', () {
  final theme = AppTheme.dark(fontFamily: 'MiSans');
  expect(theme.scaffoldBackgroundColor, const Color(0xFF0D1117));
  expect(theme.colorScheme.primary, const Color(0xFF78A9D4));
  expect(theme.colorScheme.surface, const Color(0xFF151B24));
  expect(theme.textTheme.bodyMedium?.fontFamily, 'MiSans');
});
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `D:\flutter\bin\flutter.bat test test\app_theme_test.dart`

Expected: compilation fails because `lib/theme/app_theme.dart` does not exist.

- [ ] **Step 3: Implement `AppTheme` and wire it into the app**

Expose `AppTheme.light`, `AppTheme.dark`, `AppTheme.fromDynamic`, and `AppTheme.withOledBackground`. Each method must preserve the existing progress indicator, slider, page transition, and font settings while applying shared component themes.

```dart
abstract final class AppTheme {
  static const brandBlue = Color(0xFF78A9D4);
  static const darkBackground = Color(0xFF0D1117);
  static const darkSurface = Color(0xFF151B24);

  static ThemeData dark({String? fontFamily}) => _build(
        brightness: Brightness.dark,
        fontFamily: fontFamily,
      );
}
```

Replace duplicated `ThemeData` construction in `app_widget.dart` and `theme_settings_page.dart` with the factory. Keep stored custom color and dynamic-color behavior available.

- [ ] **Step 4: Run theme tests and existing lifecycle tests**

Run: `D:\flutter\bin\flutter.bat test test\app_theme_test.dart test\app_widget_lifecycle_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit the theme boundary**

```powershell
git add lib/theme/app_theme.dart lib/app_widget.dart lib/pages/settings/theme_settings_page.dart test/app_theme_test.dart
git commit -m "建立看影音品牌主题"
```

### Task 2: Replace the Kazumi-style shell with a width-driven desktop shell

**Files:**
- Modify: `lib/pages/navigation/navigation_config.dart`
- Modify: `lib/pages/menu/menu.dart`
- Modify: `lib/pages/my/my_page.dart`
- Test: `test/navigation_config_test.dart`
- Create: `test/desktop_shell_test.dart`

- [ ] **Step 1: Write failing navigation semantics tests**

Update the expected destination labels and order to `本地媒体库`, `网盘媒体库`, and `设置`. Assert that local remains the default route and the settings destination stays last.

```dart
expect(appNavigationDestinations.map((item) => item.label), [
  '本地媒体库',
  '网盘媒体库',
  '设置',
]);
expect(appNavigationDestinations.first.path, '/local');
```

- [ ] **Step 2: Write failing shell breakpoint tests**

Pump `ScaffoldMenu` through a testable shell layout boundary at 1280 px, 760 px, and 520 px. Assert expanded labels, compact rail, and bottom navigation respectively. Use stable keys: `desktop-sidebar-expanded`, `desktop-sidebar-compact`, and `compact-bottom-navigation`.

- [ ] **Step 3: Run both tests and confirm RED**

Run: `D:\flutter\bin\flutter.bat test test\navigation_config_test.dart test\desktop_shell_test.dart`

Expected: label/order assertions fail and shell keys are missing.

- [ ] **Step 4: Implement the width-driven shell**

Use `LayoutBuilder` with these breakpoints:

```dart
const compactNavigationBreakpoint = 640.0;
const expandedSidebarBreakpoint = 960.0;
```

At 960 px and above, render a 216 px sidebar with the 看影音 wordmark and destination labels. From 640 px through 959 px, render a 72 px compact rail. Below 640 px, render bottom navigation. Preserve the 40 px drag area, Windows controls, route navigation, animation duration, curve, and navigation hiding behavior.

Use `surface` and `surfaceContainerLow` for the shell. Do not paint the whole content area with `primaryContainer`. Use a 12 px content radius only in the expanded and compact rail layouts.

- [ ] **Step 5: Rename the visible settings page**

Change the page title from `我的` to `设置`. Do not rename routes or modules in this task.

- [ ] **Step 6: Run shell and navigation tests**

Run: `D:\flutter\bin\flutter.bat test test\navigation_config_test.dart test\desktop_shell_test.dart test\widget_test.dart`

Expected: all tests pass without overflow exceptions.

- [ ] **Step 7: Commit the shell refresh**

```powershell
git add lib/pages/navigation/navigation_config.dart lib/pages/menu/menu.dart lib/pages/my/my_page.dart test/navigation_config_test.dart test/desktop_shell_test.dart
git commit -m "重做桌面导航框架"
```

### Task 3: Make media cards readable before hover

**Files:**
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: Replace hover-only card expectations with failing persistent-content tests**

Pump a local card without pointer hover and assert that the title and primary metadata are visible. Assert that hover-only quick actions remain hidden until a pointer enters.

```dart
expect(find.text('测试动画'), findsOneWidget);
expect(find.textContaining('第 1 季'), findsOneWidget);
expect(find.byKey(const ValueKey('media-card-hover-actions')), findsNothing);
```

Assert the grid uses `maxCrossAxisExtent: 220`, 12 px spacing, and a card aspect ratio sized for a 2:3 poster plus two text rows.

- [ ] **Step 2: Run local and cloud presentation tests and confirm RED**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart`

Expected: persistent title and density assertions fail against the hover-overlay implementation.

- [ ] **Step 3: Split poster and metadata responsibilities inside the shared card**

Render the poster in an `AspectRatio(aspectRatio: 2 / 3)` and render title plus one metadata line below it. Keep badges on a bottom poster scrim and show them only when they communicate an actionable state. Preserve Enter, Space, primary click, long press, and secondary click behavior.

Use the existing 160 ms `Curves.easeOut` hover animation for the play affordance and subtle surface lift. Do not add a scale animation that can cause grid clipping.

- [ ] **Step 4: Normalize cover fitting and cloud usage**

Use `BoxFit.cover` for local, cached, and network posters. Make `CloudResourcePosterWall` use the same 220 px grid density and shared card layout.

- [ ] **Step 5: Run local and cloud card tests**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart test\cloud_tmdb_library_ui_test.dart`

Expected: all tests pass.

- [ ] **Step 6: Commit the shared card refresh**

```powershell
git add lib/features/library/presentation/immersive_media_card.dart lib/features/library/presentation/library_media_grid.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "优化媒体卡片浏览体验"
```

### Task 4: Reduce toolbar action density

**Files:**
- Modify: `lib/features/library/presentation/library_path_bar.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: Write failing local toolbar tests**

Assert that `选择目录`, `媒体源`, `扫描媒体库`, `媒体库`, `刷新`, and breadcrumbs remain directly accessible. Assert `获取海报`, `读取媒体信息`, `生成缩略图`, and `批量刮削 TMDB 信息` appear only after opening a `更多媒体操作` menu.

- [ ] **Step 2: Write failing cloud toolbar tests**

Assert source selection, source management, and refresh stay visible. Assert auto-organize, scrape, and remove-source actions appear in a `更多网盘操作` menu, with remove-source rendered as an error-colored menu item.

- [ ] **Step 3: Run targeted tests and confirm RED**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart`

Expected: tests find the existing direct icon buttons and cannot find the new menus.

- [ ] **Step 4: Implement both action menus**

Use typed enums for popup values. Keep existing callback enablement conditions and busy indicators. A busy secondary action remains visible in the menu with a 16 px progress indicator and cannot be invoked twice.

- [ ] **Step 5: Run toolbar tests**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart`

Expected: all tests pass.

- [ ] **Step 6: Commit toolbar simplification**

```powershell
git add lib/features/library/presentation/library_path_bar.dart lib/pages/cloud/resources/cloud_resources_page.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "精简媒体库工具栏"
```

### Task 5: Remove visible legacy wording without removing attribution

**Files:**
- Modify: `lib/pages/settings/interface_settings.dart`
- Modify: `lib/pages/about/about_page.dart`
- Modify: `test/about_page_content_test.dart`
- Create: `test/interface_settings_content_test.dart`

- [ ] **Step 1: Write failing wording tests**

Assert the startup-page fallback is `本地媒体库` and the source file no longer contains a fallback `推荐`. Assert the about page contains the heading `开源许可与致谢` and still contains `Kazumi`.

- [ ] **Step 2: Run wording tests and confirm RED**

Run: `D:\flutter\bin\flutter.bat test test\about_page_content_test.dart test\interface_settings_content_test.dart`

Expected: fallback and heading assertions fail.

- [ ] **Step 3: Implement the wording changes**

Use `defaultStartupPageLabels[defaultPage] ?? '本地媒体库'`. Move the existing attribution text under a visible `开源许可与致谢` section without changing its URL.

- [ ] **Step 4: Run wording tests**

Run: `D:\flutter\bin\flutter.bat test test\about_page_content_test.dart test\interface_settings_content_test.dart`

Expected: all tests pass.

- [ ] **Step 5: Commit wording cleanup**

```powershell
git add lib/pages/settings/interface_settings.dart lib/pages/about/about_page.dart test/about_page_content_test.dart test/interface_settings_content_test.dart
git commit -m "清理界面遗留文案"
```

### Task 6: Version, verify, package, and preserve rollback

**Files:**
- Modify: `pubspec.yaml`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: Confirm the installed version record**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName
```

Expected before update: `2.1.35.0`.

- [ ] **Step 2: Update the patch version**

Set `version` to `2.1.36+20136` and `msix_config.msix_version` to `2.1.36.0`. Add user-facing release notes for the independent desktop shell, readable media cards, and simplified media-library actions.

- [ ] **Step 3: Run release consistency tests**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart`

Expected: all tests pass.

- [ ] **Step 4: Run formatting, the full test suite, and analysis**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: each command exits with code 0 and analysis reports no issues.

- [ ] **Step 5: Build Windows Release and create MSIX**

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
D:\flutter\bin\dart.bat run msix:create --build-windows false
```

Expected: both commands exit with code 0.

- [ ] **Step 6: Verify and copy the installer**

Locate the newest MSIX under `build\windows\x64\runner\Release`, extract `AppxManifest.xml`, and assert `Identity Version="2.1.36.0"`. Confirm the Release executable and `data\app.so` timestamps belong to this build. Copy the installer to `%USERPROFILE%\Desktop\看影音-2.1.36.msix`.

- [ ] **Step 7: Review and commit only this iteration**

Run `git status --short`, `git diff --check`, and inspect the complete diff. Exclude generated build output and unrelated files.

```powershell
git add pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
git commit -m "发布桌面界面优化测试版"
```

- [ ] **Step 8: Preserve the isolated rollback point**

Keep branch `codex/ui-refresh-v1` and worktree `D:\KanYingYin\.worktrees\ui-refresh-v1` intact. Do not merge into `main`, install the MSIX, delete the worktree, or push the branch without an explicit user request.
