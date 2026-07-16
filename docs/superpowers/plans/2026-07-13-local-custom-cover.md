# 本地视频自定义封面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 允许用户为本地视频剧集选择并保存自定义封面。

**Architecture:** `LocalCustomCoverService` 只处理目录内 `cover.*` 的替换和文件复制。`LocalPage` 负责打开图片选择器、调用服务、刷新控制器并向用户反馈结果。

**Tech Stack:** Flutter、Dart `dart:io`、`file_picker`、`path`、flutter_test。

---

### Task 1: 自定义封面文件服务

**Files:**
- Create: `lib/services/local_custom_cover_service.dart`
- Test: `test/local_custom_cover_service_test.dart`

- [x] **Step 1: Write the failing test**

```dart
test('保存自定义封面会替换已有 cover 文件并保留图片扩展名', () async {
  final result = await LocalCustomCoverService().saveForVideo(
    videoPath: video.path,
    imagePath: image.path,
  );
  expect(result, '${tempDir.path}${Platform.pathSeparator}cover.png');
  expect(await File(result!).readAsBytes(), [1, 2, 3]);
  expect(await File('${tempDir.path}${Platform.pathSeparator}cover.jpg').exists(), isFalse);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `D:\flutter\bin\flutter.bat test test\local_custom_cover_service_test.dart`

Expected: FAIL because `LocalCustomCoverService` does not exist.

- [x] **Step 3: Write minimal implementation**

```dart
Future<String?> saveForVideo({required String videoPath, required String imagePath}) async {
  final extension = p.extension(imagePath).toLowerCase();
  if (!LocalCoverFinder.posterExtensions.contains(extension)) return null;
  final directory = Directory(p.dirname(videoPath));
  for (final candidate in LocalCoverFinder.posterExtensions) {
    final file = File(p.join(directory.path, 'cover$candidate'));
    if (await file.exists()) await file.delete();
  }
  final target = File(p.join(directory.path, 'cover$extension'));
  await File(imagePath).copy(target.path);
  return target.path;
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `D:\flutter\bin\flutter.bat test test\local_custom_cover_service_test.dart`

Expected: PASS.

### Task 2: 本地页面操作入口

**Files:**
- Modify: `lib/pages/local/local_page.dart`

- [x] **Step 1: Add image selection handler**

```dart
final result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  dialogTitle: '选择自定义封面',
);
```

- [x] **Step 2: Save and refresh after selection**

```dart
final savedPath = await LocalCustomCoverService().saveForVideo(
  videoPath: group.firstEpisode.path,
  imagePath: selectedPath,
);
if (savedPath == null) return;
await localController.refresh();
```

- [x] **Step 3: Add the menu item before online cover search**

```dart
ListTile(
  leading: const Icon(Icons.add_photo_alternate_outlined),
  title: const Text('自定义封面'),
  onTap: () { /* close menu then invoke handler */ },
),
```

### Task 3: 版本与验证

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [x] **Step 1: Update versions**

Set application version to `2.3.60+20360`, MSIX version to `2.3.60.0`, and API version constant to `2.3.60`.

- [x] **Step 2: Add user-facing release notes**

Add a 2.3.60 entry explaining that local video menus can set a custom poster and the change appears immediately.

- [x] **Step 3: Verify**

Run: `D:\flutter\bin\flutter.bat test test\local_custom_cover_service_test.dart`

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: both commands exit with code 0.

- [x] **Step 4: Commit**

Run: `git add lib/services/local_custom_cover_service.dart test/local_custom_cover_service_test.dart lib/pages/local/local_page.dart pubspec.yaml lib/request/config/api_endpoints.dart RELEASE_NOTES.md lib/utils/version_history.dart docs/superpowers/plans/2026-07-13-local-custom-cover.md && git commit -m "feat: 支持本地视频自定义封面"`
