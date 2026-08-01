# Android Anime4K Auto Renderer Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 自动渲染器按 media-kit 的实际 GPU 默认后端正确启用 Anime4K。

**Architecture:** 修复集中在平台能力层，不改播放器初始化配置和用户设置。运行时偏好与设置页继续复用 `PlayerPlatformPolicy.supportsAnime4k`，因此一次能力修正即可消除两个入口的不兼容误判。

**Tech Stack:** Flutter、Dart、media_kit_video 2.0.1、Flutter Test

---

### Task 1: 对齐 Android 自动渲染器能力

**Files:**
- Modify: `lib/platform/app_platform.dart`
- Test: `test/player_platform_policy_test.dart`
- Test: `test/player_runtime_preferences_test.dart`

- [x] **Step 1: 编写失败的策略与运行时测试**

在 Android 平台策略测试中增加：

```dart
expect(policy.supportsAnime4k('auto'), isTrue);
```

把 Android 默认运行时测试的断言改为：

```dart
expect(value.videoRenderer, isNull);
expect(value.anime4kSupported, isTrue);
```

- [x] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test/player_platform_policy_test.dart test/player_runtime_preferences_test.dart`

Expected: FAIL，`auto` 和默认运行时的 `anime4kSupported` 当前均为 `false`。

- [x] **Step 3: 实现最小能力修复**

在 `AppPlatformCapabilities.supportsAnime4k` 中把 Android `auto` 纳入支持范围，并用中文注释记录 media-kit Android 默认后端：

```dart
bool supportsAnime4k(String renderer) {
  if (isWindows) return true;
  // media_kit_video 在 Android 未指定 vo 时默认使用 gpu。
  return renderer == 'auto' || renderer == 'gpu' || renderer == 'gpu-next';
}
```

- [x] **Step 4: 运行针对性测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test/player_platform_policy_test.dart test/player_runtime_preferences_test.dart test/anime4k_policy_test.dart test/anime4k_player_controller_test.dart test/anime4k_shader_executor_test.dart test/anime4k_player_ui_test.dart test/android_player_media_compatibility_test.dart`

Expected: PASS。

- [x] **Step 5: 格式化并静态检查**

Run: `D:\flutter\bin\dart.bat format lib/platform/app_platform.dart test/player_platform_policy_test.dart test/player_runtime_preferences_test.dart`

Expected: 三个文件格式化完成。

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`
