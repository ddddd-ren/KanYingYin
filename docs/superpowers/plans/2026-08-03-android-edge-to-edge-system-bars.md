# Android 边到边系统栏联动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 普通页面的状态栏和手势区与界面同色，播放器切换为黑色系统栏并在全屏时保持彻底沉浸。

**Architecture:** 原生层只控制边到边几何、系统栏显隐和生命周期恢复；Flutter 根级样式组件控制普通主题颜色与图标明暗，播放页用局部样式覆盖。底部导航用同色容器包裹安全区，Windows 直接返回原组件。

**Tech Stack:** Flutter 3.41.9、Material 3、`SystemUiOverlayStyle`、Kotlin、Android `WindowInsetsController`、JUnit 4、Flutter Widget Test。

---

## 文件职责

- Create: `lib/platform/android/android_system_ui_surface.dart`：构造普通页面和播放页面的系统栏样式，按平台包裹背景。
- Create: `test/android_system_ui_surface_test.dart`：验证浅色、深色、OLED、播放器及 Windows 无影响。
- Modify: `lib/app_widget.dart`：在 `MaterialApp.router.builder` 接入普通页面系统栏表面。
- Modify: `lib/bean/appbar/sys_app_bar.dart`：复用统一普通页面样式，避免 AppBar 覆盖根级图标设置。
- Modify: `lib/pages/menu/adaptive_navigation_shell.dart`：让底部安全区与 `NavigationBar` 同色。
- Modify: `test/adaptive_navigation_android_test.dart`：验证底部同色安全区结构。
- Modify: `lib/pages/video/video_page.dart`：发布播放器黑色系统栏样式并提供黑色底层。
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt`：保存沉浸请求并始终重放当前模式。
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt`：实现普通边到边与全屏沉浸两态。
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`：启动和生命周期边界应用当前模式。
- Modify: `android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt`：验证初始化、进入、退出和重放。
- Modify: `test/android_player_media_compatibility_test.dart`：锁定正常模式不恢复 `setDecorFitsSystemWindows(true)`。

## 执行顺序

本计划可独立于夸克性能计划执行；完成后仍需执行 `2026-08-03-v2.1.103-integration-delivery.md` 才形成用户可安装测试包。

### Task 1: 用 TDD 新增统一 Flutter 系统栏表面

**Files:**
- Create: `test/android_system_ui_surface_test.dart`
- Create: `lib/platform/android/android_system_ui_surface.dart`

- [ ] **Step 1: 写普通页面浅色与深色失败测试**

创建 `test/android_system_ui_surface_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_system_ui_surface.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  testWidgets('Android 普通页面系统栏透明且图标跟随主题', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: AndroidSystemUiSurface(
            capabilities: AppPlatformCapabilities.android,
            child: const SizedBox.expand(),
          ),
        ),
      );

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byKey(const ValueKey('android-app-system-ui')),
      );
      final expectedIcons = brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light;
      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.systemNavigationBarColor, Colors.transparent);
      expect(region.value.statusBarIconBrightness, expectedIcons);
      expect(region.value.systemNavigationBarIconBrightness, expectedIcons);
      expect(region.value.systemStatusBarContrastEnforced, isFalse);
      expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    }
  });
```

- [ ] **Step 2: 写播放器和 Windows 边界失败测试**

在同一文件增加：

```dart
testWidgets('Android 播放页面使用黑色底层和白色系统图标', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: AndroidPlaybackSystemUiSurface(
        capabilities: AppPlatformCapabilities.android,
        child: SizedBox.expand(),
      ),
    ),
  );

  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find.byKey(const ValueKey('android-player-system-ui')),
  );
  final surface = tester.widget<ColoredBox>(
    find.byKey(const ValueKey('android-player-system-ui-background')),
  );
  expect(surface.color, Colors.black);
  expect(region.value.statusBarIconBrightness, Brightness.light);
  expect(region.value.systemNavigationBarIconBrightness, Brightness.light);
});

testWidgets('Windows 不增加 Android 系统栏包装', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: AndroidSystemUiSurface(
        capabilities: AppPlatformCapabilities.windows,
        child: Text('Windows'),
      ),
    ),
  );

  expect(find.byKey(const ValueKey('android-app-system-ui')), findsNothing);
  expect(find.text('Windows'), findsOneWidget);
});
```

- [ ] **Step 3: 运行测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/android_system_ui_surface_test.dart
```

Expected: 编译失败，因为系统栏表面文件和类型尚不存在。

- [ ] **Step 4: 创建最小系统栏样式组件**

创建 `lib/platform/android/android_system_ui_surface.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/platform/app_platform.dart';

SystemUiOverlayStyle androidAppSystemUiStyle(Brightness brightness) {
  final iconBrightness = brightness == Brightness.light
      ? Brightness.dark
      : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarContrastEnforced: false,
  );
}

const SystemUiOverlayStyle androidPlaybackSystemUiStyle =
    SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

class AndroidSystemUiSurface extends StatelessWidget {
  const AndroidSystemUiSurface({
    super.key,
    required this.capabilities,
    required this.child,
  });

  final AppPlatformCapabilities capabilities;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.isAndroid) return child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('android-app-system-ui'),
      value: androidAppSystemUiStyle(Theme.of(context).brightness),
      child: ColoredBox(
        key: const ValueKey('android-app-system-ui-background'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
  }
}

class AndroidPlaybackSystemUiSurface extends StatelessWidget {
  const AndroidPlaybackSystemUiSurface({
    super.key,
    required this.capabilities,
    required this.child,
  });

  final AppPlatformCapabilities capabilities;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.isAndroid) return child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('android-player-system-ui'),
      value: androidPlaybackSystemUiStyle,
      child: ColoredBox(
        key: const ValueKey('android-player-system-ui-background'),
        color: Colors.black,
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 5: 运行组件测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/android_system_ui_surface_test.dart`

Expected: 三个测试全部通过。

- [ ] **Step 6: 提交统一样式组件**

```powershell
git diff --check
git add -- lib/platform/android/android_system_ui_surface.dart test/android_system_ui_surface_test.dart
git commit -m "功能：统一安卓系统栏页面样式"
```

### Task 2: 接入应用根部与底部导航安全区

**Files:**
- Modify: `test/adaptive_navigation_android_test.dart`
- Modify: `test/app_widget_lifecycle_test.dart`
- Modify: `lib/app_widget.dart`
- Modify: `lib/bean/appbar/sys_app_bar.dart`
- Modify: `lib/pages/menu/adaptive_navigation_shell.dart`

- [ ] **Step 1: 写底部同色安全区失败测试**

在 `adaptive_navigation_android_test.dart` 的现有测试中增加：

```dart
expect(
  find.byKey(const ValueKey<String>('compact-bottom-navigation-surface')),
  findsOneWidget,
);
final bottomSafeArea = tester.widget<SafeArea>(
  find.byKey(const ValueKey<String>('compact-bottom-navigation-safe-area')),
);
expect(bottomSafeArea.top, isFalse);
expect(bottomSafeArea.bottom, isTrue);
final bottomSurface = tester.widget<ColoredBox>(
  find.byKey(const ValueKey<String>('compact-bottom-navigation-surface')),
);
expect(
  bottomSurface.color,
  Theme.of(tester.element(find.byType(NavigationBar)))
      .colorScheme
      .surfaceContainerLow,
);
```

- [ ] **Step 2: 写应用根部接入失败测试**

在 `app_widget_lifecycle_test.dart` 增加独立源码契约测试；该文件已经导入 `dart:io`：

```dart
test('应用根部接入 Android 系统栏表面', () {
  final appWidgetSource = File('lib/app_widget.dart').readAsStringSync();

  expect(appWidgetSource, contains('AndroidSystemUiSurface('));
  expect(appWidgetSource, contains('builder: (context, child)'));
  expect(appWidgetSource, contains('capabilities: detectAppPlatform()'));
});
```

- [ ] **Step 3: 运行定向测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/adaptive_navigation_android_test.dart test/app_widget_lifecycle_test.dart
```

Expected: 缺少底部背景 Key 和根级 builder 断言失败。

- [ ] **Step 4: 在 MaterialApp 根部接入普通样式**

在 `app_widget.dart` 导入新组件，并给 `MaterialApp.router` 增加：

```dart
builder: (context, child) => AndroidSystemUiSurface(
  capabilities: detectAppPlatform(),
  child: child ?? const SizedBox.shrink(),
),
```

保留外层 `AppShellHost` 和 Windows 生命周期行为不变。

- [ ] **Step 5: 让 SysAppBar 复用统一样式**

在 `sys_app_bar.dart` 导入新组件，把内联 `SystemUiOverlayStyle(...)` 替换为：

```dart
systemOverlayStyle: androidAppSystemUiStyle(
  Theme.of(context).brightness,
),
```

删除不再直接使用的 `flutter/services.dart` 导入；其余 AppBar 高度、按钮和桌面拖动行为不变。

- [ ] **Step 6: 用同色容器包裹底部安全区**

在 `_bottomLayout` 中缓存：

```dart
final navigationColor =
    Theme.of(context).colorScheme.surfaceContainerLow;
```

把 `bottomNavigationBar` 改为：

```dart
bottomNavigationBar: ColoredBox(
  key: const ValueKey<String>('compact-bottom-navigation-surface'),
  color: navigationColor,
  child: SafeArea(
    key: const ValueKey<String>('compact-bottom-navigation-safe-area'),
    top: false,
    child: NavigationBar(
      key: const ValueKey<String>('compact-bottom-navigation'),
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (final item in destinations)
          NavigationDestination(
            selectedIcon: Icon(item.selectedIcon),
            icon: Icon(item.icon),
            label: item.label,
          ),
      ],
    ),
  ),
),
```

- [ ] **Step 7: 运行组件测试并确认 GREEN**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/android_system_ui_surface_test.dart test/adaptive_navigation_android_test.dart test/app_widget_lifecycle_test.dart test/app_theme_test.dart
```

Expected: 全部通过，Windows 壳测试不回归。

- [ ] **Step 8: 提交普通页面边到边样式**

```powershell
git diff --check
git add -- lib/app_widget.dart lib/bean/appbar/sys_app_bar.dart lib/pages/menu/adaptive_navigation_shell.dart test/adaptive_navigation_android_test.dart test/app_widget_lifecycle_test.dart
git commit -m "优化：让安卓普通页面系统栏与界面同色"
```

### Task 3: 接入播放器黑色系统栏表面

**Files:**
- Modify: `test/android_player_media_compatibility_test.dart`
- Modify: `lib/pages/video/video_page.dart`

- [ ] **Step 1: 写播放器样式失败契约**

在 `android_player_media_compatibility_test.dart` 的现有字符串字段中增加：

```dart
late String videoPage;
```

在 `setUpAll` 中增加：

```dart
videoPage = File('lib/pages/video/video_page.dart').readAsStringSync();
```

然后增加源码契约测试：

```dart
test('Android 播放页使用黑色系统栏表面', () {
  expect(videoPage, contains('AndroidPlaybackSystemUiSurface('));
  expect(videoPage, contains('backgroundColor: Colors.black'));
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/android_player_media_compatibility_test.dart test/android_system_ui_surface_test.dart
```

Expected: 播放页尚未使用局部系统栏表面，源码断言失败。

- [ ] **Step 3: 包裹播放页并设置黑色底层**

在 `video_page.dart` 导入：

```dart
import 'package:kanyingyin/platform/android/android_system_ui_surface.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
```

把当前构建方法开头的：

```dart
return PopScope(
```

替换为：

```dart
return AndroidPlaybackSystemUiSurface(
  capabilities: detectAppPlatform(),
  child: PopScope(
```

再把该 `PopScope` 当前结尾：

```dart
      }),
    );
```

替换为：

```dart
      }),
    ),
  );
```

给播放页 `Scaffold` 明确增加：

```dart
backgroundColor: Colors.black,
```

不要修改视频比例、播放器控件、字幕、侧栏或 `SafeArea` 的现有方向规则。

- [ ] **Step 4: 运行播放器测试并确认 GREEN**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/android_player_media_compatibility_test.dart test/android_system_ui_surface_test.dart test/player_back_policy_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交播放器样式**

```powershell
git diff --check
git add -- lib/pages/video/video_page.dart test/android_player_media_compatibility_test.dart
git commit -m "优化：联动安卓播放器系统栏颜色"
```

### Task 4: 用原生单元测试重构普通边到边与沉浸两态

**Files:**
- Modify: `android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`
- Modify: `test/android_player_media_compatibility_test.dart`

- [ ] **Step 1: 把控制器测试改为始终重放当前模式**

将 Kotlin 测试替换为四个明确状态测试：

```kotlin
@Test
fun initializeAppliesVisibleEdgeToEdgeMode() {
    val calls = mutableListOf<Boolean>()
    val controller = ImmersiveModeController { enabled -> calls += enabled }

    controller.initialize()

    assertFalse(controller.isRequested)
    assertEquals(listOf(false), calls)
}

@Test
fun enablingStoresRequestAndAppliesImmersiveMode() {
    val calls = mutableListOf<Boolean>()
    val controller = ImmersiveModeController { enabled -> calls += enabled }

    controller.setEnabled(true)

    assertTrue(controller.isRequested)
    assertEquals(listOf(true), calls)
}

@Test
fun lifecycleReapplyUsesCurrentRequestedMode() {
    val calls = mutableListOf<Boolean>()
    val controller = ImmersiveModeController { enabled -> calls += enabled }

    controller.initialize()
    controller.reapplyCurrent()
    controller.setEnabled(true)
    controller.reapplyCurrent()

    assertEquals(listOf(false, false, true, true), calls)
}

@Test
fun disablingReturnsToVisibleEdgeToEdgeAndKeepsReapplyingIt() {
    val calls = mutableListOf<Boolean>()
    val controller = ImmersiveModeController { enabled -> calls += enabled }

    controller.setEnabled(true)
    controller.setEnabled(false)
    controller.reapplyCurrent()

    assertFalse(controller.isRequested)
    assertEquals(listOf(true, false, false), calls)
}
```

- [ ] **Step 2: 更新 Dart 原生契约失败测试**

把旧的恢复断言：

```dart
expect(immersiveModeApplier, contains('window.setDecorFitsSystemWindows(true)'));
```

替换为：

```dart
expect(
  immersiveModeApplier,
  isNot(contains('window.setDecorFitsSystemWindows(true)')),
);
expect(
  immersiveModeApplier,
  contains('window.setDecorFitsSystemWindows(false)'),
);
expect(immersiveModeApplier, contains('show(WindowInsets.Type.systemBars())'));
expect(mainActivity, contains('immersiveModeController.initialize()'));
expect(mainActivity, contains('immersiveModeController.reapplyCurrent()'));
```

- [ ] **Step 3: 运行原生和契约测试并确认 RED**

```powershell
Push-Location android
.\gradlew.bat :app:testDebugUnitTest --no-daemon
Pop-Location
D:\flutter\bin\flutter.bat test --no-pub test/android_player_media_compatibility_test.dart
```

Expected: Kotlin 编译失败，缺少 `initialize` 和 `reapplyCurrent`；Dart 契约仍发现 `setDecorFitsSystemWindows(true)`。

- [ ] **Step 4: 实现控制器当前模式重放**

把 `ImmersiveModeController` 改为：

```kotlin
internal class ImmersiveModeController(
    private val applier: ImmersiveModeApplier,
) {
    var isRequested: Boolean = false
        private set

    fun initialize() {
        applier.apply(false)
    }

    fun setEnabled(enabled: Boolean) {
        isRequested = enabled
        applier.apply(enabled)
    }

    fun reapplyCurrent() {
        applier.apply(isRequested)
    }
}
```

- [ ] **Step 5: 把原生 Applier 的退出态改为正常边到边**

保留进入全屏时的透明系统栏、关闭对比度、白色图标和 `hide(systemBars)`。将退出实现改为：

```kotlin
private fun disableImmersiveMode() {
    applyTransparentSystemBars()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        window.setDecorFitsSystemWindows(false)
        window.insetsController?.let { controller ->
            savedState?.systemBarsAppearance?.let { appearance ->
                controller.setSystemBarsAppearance(
                    appearance,
                    lightBarAppearanceMask,
                )
            }
            savedState?.systemBarsBehavior?.let { behavior ->
                controller.systemBarsBehavior = behavior
            }
            controller.show(WindowInsets.Type.systemBars())
        }
    } else {
        val lightAppearance = (savedState?.systemUiVisibility
            ?: window.decorView.systemUiVisibility) and lightLegacyMask
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                lightAppearance
    }
    savedState = null
}
```

抽取幂等公共配置：

```kotlin
private fun applyTransparentSystemBars() {
    window.statusBarColor = Color.TRANSPARENT
    window.navigationBarColor = Color.TRANSPARENT
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        window.isStatusBarContrastEnforced = false
        window.isNavigationBarContrastEnforced = false
    }
}
```

`captureState()` 保留现有 `controller` 局部变量，但把返回值、数据类和 companion object 精确改为：

```kotlin
return SavedSystemBarState(
    systemUiVisibility = window.decorView.systemUiVisibility,
    systemBarsAppearance =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            controller?.systemBarsAppearance
        } else {
            null
        },
    systemBarsBehavior =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            controller?.systemBarsBehavior
        } else {
            null
        },
)

private data class SavedSystemBarState(
    val systemUiVisibility: Int,
    val systemBarsAppearance: Int?,
    val systemBarsBehavior: Int?,
)

private companion object {
    val lightBarAppearanceMask =
        WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
            WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS

    val lightLegacyMask =
        View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
            } else {
                0
            }
}
```

`SavedSystemBarState` 不再保存或恢复不透明颜色、对比度开关，也不再恢复 `fitsSystemWindows=true`。

- [ ] **Step 6: 在 Activity 启动及生命周期应用当前模式**

在 `onCreate` 的 `super.onCreate` 后、方向策略前增加：

```kotlin
immersiveModeController.initialize()
```

将 `onResume`、`onWindowFocusChanged` 和 `onConfigurationChanged` 的：

```kotlin
immersiveModeController.reapplyIfRequested()
```

统一替换为：

```kotlin
immersiveModeController.reapplyCurrent()
```

- [ ] **Step 7: 运行原生和契约测试并确认 GREEN**

```powershell
Push-Location android
.\gradlew.bat :app:testDebugUnitTest --no-daemon
Pop-Location
D:\flutter\bin\flutter.bat test --no-pub test/android_player_media_compatibility_test.dart test/android_system_ui_surface_test.dart test/adaptive_navigation_android_test.dart
```

Expected: Kotlin 四项状态测试通过；Dart 契约不再包含 `setDecorFitsSystemWindows(true)`。

- [ ] **Step 8: 提交原生两态控制器**

```powershell
git diff --check
git add -- android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt test/android_player_media_compatibility_test.dart
git commit -m "修复：保持安卓普通页面边到边显示"
```

### Task 5: 系统栏子系统完成门

**Files:**
- Verify: all files changed by Tasks 1-4

- [ ] **Step 1: 运行系统栏定向测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/android_system_ui_surface_test.dart test/adaptive_navigation_android_test.dart test/app_widget_lifecycle_test.dart test/app_theme_test.dart test/android_player_media_compatibility_test.dart test/player_back_policy_test.dart
Push-Location android
.\gradlew.bat :app:testDebugUnitTest --no-daemon
Pop-Location
```

Expected: Flutter 和 Kotlin 测试均 0 失败。

- [ ] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`

- [ ] **Step 3: 审查系统栏差异和提交边界**

```powershell
git status --short
git diff --check
git log -4 --oneline
```

Expected: 本计划代码全部已提交；没有版本号、夸克调度或发布文案改动。
