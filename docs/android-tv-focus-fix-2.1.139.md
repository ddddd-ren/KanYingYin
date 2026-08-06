# Android TV 焦点导航和退出交互修复 (2.1.139)

## 修复的问题

### 1. 遥控器方向键无法移动焦点到侧边导航栏

**现象**：
- Android TV 模式下，焦点一直卡在本地媒体库的右边内容栏
- 按左方向键无法将焦点移动到左侧的侧边导航栏
- 用户无法通过遥控器切换到其他页面

**根本原因**：
`adaptive_navigation_shell.dart` 中的 `_desktopLayout` 方法存在焦点遍历策略问题：
- 导航栏和内容区分别被包在独立的 `FocusTraversalGroup` 中
- 这两个 `FocusTraversalGroup` 是兄弟关系，没有共同的父级遍历策略
- 默认情况下，焦点被困在当前组内，无法跨越到兄弟组

**修复方案**：
在 `Row` 外层添加带 `WidgetOrderTraversalPolicy` 的 `FocusTraversalGroup`：
```dart
Expanded(
  child: FocusTraversalGroup(
    policy: WidgetOrderTraversalPolicy(),
    child: Row(
      children: [
        FocusTraversalGroup(
          key: const ValueKey<String>('tv-navigation-focus-group'),
          child: wrappedNavigation,
        ),
        Expanded(
          child: FocusTraversalGroup(
            key: const ValueKey<String>('tv-content-focus-group'),
            child: content,
          ),
        ),
      ],
    ),
  ),
)
```

### 2. 遥控器返回键无法收回文件夹展开

**现象**：
- 在本地媒体库中，点击地址栏展开文件夹下拉菜单后
- 按返回键不会关闭下拉菜单，而是直接弹出退出应用的对话框

**根本原因**：
`directory_address_dropdown.dart` 中的 `MenuAnchor` 没有处理返回键事件：
- 当下拉菜单展开时，返回键事件被直接传递到 `TvBackNavigationGuard`
- `TvBackNavigationGuard` 拦截到返回键后直接弹出退出对话框

**修复方案**：
在 `TextField` 外包裹 `CallbackShortcuts`，拦截 ESC 键并关闭菜单：
```dart
CallbackShortcuts(
  bindings: <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (controller.isOpen) {
        controller.close();
      }
    },
  },
  child: TextField(...),
)
```

### 3. 弹出退出弹窗后按返回键直接退出应用

**现象**：
- Android TV 模式下，按返回键弹出"退出看影音？"对话框
- 在对话框显示时再次按返回键，应用直接退出
- 没有给用户取消的机会

**根本原因**：
`tv_back_navigation_guard.dart` 的退出对话框 `PopScope.onPopInvokedWithResult` 处理有误：
```dart
onPopInvokedWithResult: (didPop, _) {
  if (didPop) return;
  Navigator.of(dialogContext).pop(false);
  unawaited(_requestExit());  // 错误：直接退出应用
},
```

**修复方案**：
移除 `_requestExit()` 调用，只关闭对话框并返回 `false`：
```dart
onPopInvokedWithResult: (didPop, _) {
  if (didPop) return;
  Navigator.of(dialogContext).pop(false);  // 只关闭对话框
},
```
同时更新对话框文案，明确告知用户必须点击"退出"按钮：
```dart
content: const Text('请点击"退出"按钮关闭应用。'),
```

## 修改的文件

### 1. lib/pages/menu/adaptive_navigation_shell.dart
- 在 `_desktopLayout` 方法中为 `Row` 添加父级 `FocusTraversalGroup`
- 使用 `WidgetOrderTraversalPolicy` 策略允许焦点在导航栏和内容区之间切换

### 2. lib/features/tv/presentation/tv_back_navigation_guard.dart
- 修复退出对话框的 `PopScope.onPopInvokedWithResult` 逻辑
- 更新对话框文案，明确退出操作必须点击按钮

### 3. lib/features/library/presentation/directory_address_dropdown.dart
- 添加 `flutter/services.dart` 导入
- 在 `TextField` 外包裹 `CallbackShortcuts` 拦截 ESC 键

### 4. test/tv_back_navigation_guard_test.dart
- 更新测试名称：从"连续返回才退出应用"改为"必须点击退出按钮才退出应用"
- 修改测试断言：第三次按返回键后 `exitCount` 应为 `0` 而非 `1`

### 5. pubspec.yaml
- 版本号从 `2.1.138+20138` 更新为 `2.1.139+20139`

### 6. lib/utils/version_history.dart
- 添加 2.1.139 版本历史记录

### 7. RELEASE_NOTES.md
- 添加 2.1.139 版本更新说明

## 测试验证

### 运行的测试
```bash
flutter analyze  # 静态分析通过
flutter test test/tv_back_navigation_guard_test.dart  # 2/2 通过
flutter test test/adaptive_navigation_android_test.dart  # 3/3 通过
```

### 测试覆盖
- ✅ TV 返回键先退出输入，再确认，必须点击退出按钮才退出应用
- ✅ TV 退出确认可用遥控器按钮取消或退出
- ✅ Android TV 宽屏保持带文字的侧栏并建立焦点组
- ✅ Android TV 内容区按左键后焦点进入侧栏

## 用户体验改进

1. **焦点导航**：Android TV 用户现在可以使用遥控器左右键在侧边导航栏和内容区之间自由切换
2. **菜单关闭**：文件夹下拉菜单可以正常用返回键关闭，不会误触退出应用
3. **退出确认**：退出应用需要明确点击"退出"按钮，避免误操作

## 技术要点

### FocusTraversalPolicy
Flutter 的焦点遍历策略控制焦点如何在 widget 之间移动：
- `WidgetOrderTraversalPolicy`：按 widget 树的顺序遍历
- 需要在父级设置策略才能让子级 `FocusTraversalGroup` 之间互相导航

### CallbackShortcuts
用于拦截键盘快捷键并执行回调：
- ESC 键在 Android TV 上映射为返回键
- 通过拦截 ESC 键可以在 `MenuAnchor` 展开时阻止事件向上传播

### PopScope
Flutter 3.12+ 用于处理返回导航的 widget：
- `canPop`: 是否允许直接弹出
- `onPopInvokedWithResult`: 返回导航发生时的回调
- `didPop` 参数指示是否已经弹出，用于区分不同的处理逻辑
