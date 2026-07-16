# 视频识别大小限制设置实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为本地媒体库与 OpenList 媒体库提供相互独立、可持久化的最小视频文件大小设置，并允许保存后选择是否立即重扫。

**Architecture:** 新增独立的 `MediaRecognitionSettings` 服务负责字节阈值、Hive 持久化、输入校验与显示格式。扫描服务通过可注入的阈值读取函数在每次扫描开始时获取最新设置，并把阈值写入目录指纹以使降低阈值时旧缓存失效；设置页面只负责编辑和确认重扫，通过回调调用既有本地与网盘控制器。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Flutter Modular、Hive CE、MobX、flutter_test、media_kit、MSIX。

---

## 文件结构

- Create: `lib/services/media_recognition_settings.dart`：设置模型、校验、单位换算、显示格式和 Hive 存储适配。
- Create: `lib/pages/settings/media_recognition_settings.dart`：本地与网盘阈值设置页面、选择面板、自定义输入和重扫确认。
- Create: `test/media_recognition_settings_test.dart`：设置服务单元测试。
- Create: `test/media_recognition_settings_ui_test.dart`：入口、预设、自定义校验和重扫回调组件测试。
- Modify: `lib/utils/storage.dart`：新增两个稳定的设置键。
- Modify: `lib/services/local_media_scanner.dart`：每次扫描读取本地阈值。
- Modify: `lib/services/local_media_indexer.dart`：每次索引读取本地阈值并纳入目录指纹。
- Modify: `lib/services/cloud/cloud_media_indexer.dart`：每次扫描读取网盘阈值并纳入目录指纹。
- Modify: `lib/providers/cloud_library_controller.dart`：顺序扫描所有 OpenList 来源。
- Modify: `lib/pages/index_module.dart`：注册设置服务并向三个扫描器注入动态阈值读取函数。
- Modify: `lib/pages/settings/settings_module.dart`：注册媒体识别设置路由与重扫回调。
- Modify: `lib/pages/my/my_page.dart`：增加“媒体识别”入口。
- Modify: `test/local_media_scanner_test.dart`、`test/local_media_indexer_test.dart`、`test/cloud_media_indexer_test.dart`、`test/cloud_library_controller_test.dart`：动态阈值和重扫回归测试。
- Modify: `pubspec.yaml`、`lib/request/config/api_endpoints.dart`、`UPDATE_DIALOG_COPY.md`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：发布版本更新。

### Task 1: 建立强类型设置与持久化边界

**Files:**
- Create: `lib/services/media_recognition_settings.dart`
- Create: `test/media_recognition_settings_test.dart`
- Modify: `lib/utils/storage.dart`

- [ ] **Step 1: 写设置服务失败测试**

测试使用内存实现覆盖默认值、本地与网盘互不影响、异常存储回退、`0 MB`、最大 `1048576 MB`、超限拒绝和显示文本：

```dart
test('本地与网盘识别限制分别保存并转换为字节', () async {
  final storage = MemoryRecognitionSettingsStorage();
  final settings = MediaRecognitionSettings(storage: storage);

  expect(settings.localMinSizeBytes, 800 * 1024 * 1024);
  expect(settings.cloudMinSizeBytes, 1024 * 1024);

  await settings.saveMegabytes(MediaRecognitionTarget.local, 50);
  await settings.saveMegabytes(MediaRecognitionTarget.cloud, 0);

  expect(settings.localMinSizeBytes, 50 * 1024 * 1024);
  expect(settings.cloudMinSizeBytes, 0);
  expect(settings.formatMegabytes(0), '不限制');
  expect(settings.formatMegabytes(1024), '1 GB');
});

test('自定义限制拒绝负数与超过 1 TB 的值', () async {
  final settings = MediaRecognitionSettings(
    storage: MemoryRecognitionSettingsStorage(),
  );
  expect(() => settings.validateMegabytes(-1), throwsFormatException);
  expect(() => settings.validateMegabytes(1048577), throwsFormatException);
});
```

- [ ] **Step 2: 运行测试并确认因类型尚不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\media_recognition_settings_test.dart`

Expected: FAIL，提示 `MediaRecognitionSettings` 等符号未定义。

- [ ] **Step 3: 实现最小设置服务**

新增两个存储键 `localMinRecognizedVideoSizeBytes`、`cloudMinRecognizedVideoSizeBytes`。实现以下公开边界：

```dart
enum MediaRecognitionTarget { local, cloud }

abstract interface class RecognitionSettingsStorage {
  Object? read(String key);
  Future<void> write(String key, int value);
}

class MediaRecognitionSettings {
  static const bytesPerMegabyte = 1024 * 1024;
  static const maxMegabytes = 1024 * 1024;
  static const localDefaultBytes = 800 * bytesPerMegabyte;
  static const cloudDefaultBytes = bytesPerMegabyte;
  static const presetMegabytes = <int>[0, 1, 10, 50, 100, 500, 800, 1024];

  int get localMinSizeBytes => _readBytes(
        SettingBoxKey.localMinRecognizedVideoSizeBytes,
        localDefaultBytes,
      );
  int get cloudMinSizeBytes => _readBytes(
        SettingBoxKey.cloudMinRecognizedVideoSizeBytes,
        cloudDefaultBytes,
      );

  int validateMegabytes(int value) {
    if (value < 0 || value > maxMegabytes) throw const FormatException();
    return value;
  }
}
```

Hive 适配器是默认存储实现；测试内存实现只放在测试文件。读取值必须验证 `int`、非负且不超过 1 TB 对应字节数，否则回退默认值。

- [ ] **Step 4: 运行设置服务测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\media_recognition_settings_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交设置服务**

```powershell
git add -- lib/services/media_recognition_settings.dart lib/utils/storage.dart test/media_recognition_settings_test.dart
git commit -m "新增媒体识别大小设置"
```

### Task 2: 让本地扫描动态使用限制

**Files:**
- Modify: `lib/services/local_media_scanner.dart`
- Modify: `lib/services/local_media_indexer.dart`
- Modify: `test/local_media_scanner_test.dart`
- Modify: `test/local_media_indexer_test.dart`

- [ ] **Step 1: 写动态阈值与缓存失效失败测试**

扫描器测试用可变变量作为 provider，先以 800 MB 忽略文件，再改为 1 MB 并用同一实例扫描，断言文件被识别。索引器测试建立相同目录内容，第一次高阈值建立指纹，降低阈值后再次索引，断言之前被过滤的文件加入索引而不是复用旧目录。

```dart
var minBytes = 800 * 1024 * 1024;
final scanner = LocalMediaScanner(
  minRecognizedVideoSizeBytesProvider: () => minBytes,
);
expect((await scanner.scan(path, sortMode: LocalSortMode.name, ascending: true)).items, isEmpty);
minBytes = 1024 * 1024;
expect((await scanner.scan(path, sortMode: LocalSortMode.name, ascending: true)).items, hasLength(1));
```

- [ ] **Step 2: 运行定向测试并确认 provider 参数不存在或旧缓存被复用**

Run: `D:\flutter\bin\flutter.bat test test\local_media_scanner_test.dart test\local_media_indexer_test.dart`

Expected: FAIL，原因是动态 provider 尚未实现。

- [ ] **Step 3: 实现每次操作读取阈值**

为两个构造器增加兼容现有固定整数参数的 provider：

```dart
int Function()? minRecognizedVideoSizeBytesProvider,
int minRecognizedVideoSizeBytes = LocalVideoFileTypes.minRecognizedVideoSizeBytes,
```

构造时保存 `_minRecognizedVideoSizeBytesProvider = provider ?? () => minRecognizedVideoSizeBytes`。在 `scan`/`indexSource` 开头读取一次局部 `minSizeBytes`，本次操作内保持一致。

本地索引目录指纹加入阈值：

```dart
final fingerprint = await _directoryFingerprint(
  entries,
  minSizeBytes: minSizeBytes,
);

return 'minSizeBytes=$minSizeBytes\n${parts.join('\n')}';
```

所有大小判断改用本次操作的 `minSizeBytes`。`isRecognizedVideoSize` 调整为：阈值为零时仍要求文件大小大于零。

- [ ] **Step 4: 运行本地扫描定向测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\local_media_scanner_test.dart test\local_media_indexer_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交本地扫描改动**

```powershell
git add -- lib/services/local_video_file_types.dart lib/services/local_media_scanner.dart lib/services/local_media_indexer.dart test/local_media_scanner_test.dart test/local_media_indexer_test.dart
git commit -m "支持动态本地视频大小限制"
```

### Task 3: 让 OpenList 扫描动态使用独立限制

**Files:**
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Modify: `test/cloud_media_indexer_test.dart`

- [ ] **Step 1: 写网盘阈值与未变目录缓存失败测试**

用同一个 `CloudMediaIndexer` 和内存仓储扫描内容不变的目录；第一次以 100 MB 排除 50 MB 视频，修改 provider 为 10 MB 后再次扫描，断言视频被加入：

```dart
var minBytes = 100 * 1024 * 1024;
final indexer = CloudMediaIndexer(
  repository: repository,
  minRecognizedVideoSizeBytesProvider: () => minBytes,
);
expect((await indexer.scan(source: source, client: client)).videoCount, 0);
minBytes = 10 * 1024 * 1024;
expect((await indexer.scan(source: source, client: client)).videoCount, 1);
```

- [ ] **Step 2: 运行测试并确认因 provider 不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_indexer_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现网盘阈值读取与指纹失效**

新增 `minRecognizedVideoSizeBytesProvider`，默认仍为 1 MB。每次 `_scan` 开头读取一次，并传入视频过滤与 `_fingerprint`：

```dart
static String _fingerprint(
  String path,
  List<CloudFileEntry> entries, {
  required int minSizeBytes,
}) {
  return sha256.convert(utf8.encode(jsonEncode(<String, Object?>{
    'path': _normalizePath(path),
    'minSizeBytes': minSizeBytes,
    'children': children,
  }))).toString();
}
```

阈值改变会使目录指纹变化，从而跳过“不变目录直接返回旧索引”的分支。

- [ ] **Step 4: 运行网盘索引测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_indexer_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交网盘扫描改动**

```powershell
git add -- lib/services/cloud/cloud_media_indexer.dart test/cloud_media_indexer_test.dart
git commit -m "支持独立网盘视频大小限制"
```

### Task 4: 接入依赖、设置页面与对应类型重扫

**Files:**
- Create: `lib/pages/settings/media_recognition_settings.dart`
- Create: `test/media_recognition_settings_ui_test.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/my/my_page.dart`
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `test/cloud_library_controller_test.dart`
- Modify: `test/navigation_config_test.dart`

- [ ] **Step 1: 写入口、交互与重扫失败测试**

组件测试断言页面包含“本地媒体库”“网盘媒体库”“800 MB”“1 MB”；选择预设后出现“是否立即重新扫描”，点“立即扫描”只调用对应回调；自定义输入 `-1`、小数、`1048577` 时显示错误且不保存。控制器测试断言 `scanAllSources()` 按仓储顺序逐个调用来源，某一来源失败时记录错误并继续下一来源。

- [ ] **Step 2: 运行 UI 与控制器测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\media_recognition_settings_ui_test.dart test\cloud_library_controller_test.dart test\navigation_config_test.dart`

Expected: FAIL，页面、路由及批量扫描方法尚不存在。

- [ ] **Step 3: 实现顺序扫描所有网盘来源**

在 `CloudLibraryController` 增加：

```dart
Future<int> scanAllSources() async {
  await load();
  var completed = 0;
  for (final source in List<CloudSource>.of(sources)) {
    try {
      await scanSource(source.id);
      completed++;
    } on Object {
      // 单个来源失败时继续处理其余来源。
    }
  }
  return completed;
}
```

保留现有单来源串行限制，不并发发起网络扫描。

- [ ] **Step 4: 实现设置页与选择面板**

页面构造器保持可测试依赖：

```dart
class MediaRecognitionSettingsPage extends StatefulWidget {
  const MediaRecognitionSettingsPage({
    super.key,
    required this.settings,
    required this.onRescanLocal,
    required this.onRescanCloud,
  });

  final MediaRecognitionSettings settings;
  final Future<void> Function() onRescanLocal;
  final Future<void> Function() onRescanCloud;
}
```

使用现有 `SettingsList`、`SettingsSection`、`SettingsTile.navigation` 样式。预设以菜单或底部面板展示；自定义输入只允许整数，错误文案分别为“请输入非负整数”和“最大支持 1048576 MB”。保存后使用标准 `AlertDialog` 提供“稍后”和“立即扫描”。扫描期间禁用重复提交并显示进度指示。

- [ ] **Step 5: 注册生产依赖和路由**

在 `IndexModule` 注册单例设置服务，并向本地 scanner/indexer 与 cloud indexer 注入：

```dart
minRecognizedVideoSizeBytesProvider:
    () => Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
```

网盘使用 `cloudMinSizeBytes`。设置路由 `/settings/media-recognition` 的本地回调调用 `LocalController.refreshLocalLibraryIndex()`，网盘回调调用 `CloudLibraryController.scanAllSources()` 后调用 `LocalController.reloadCloudLibraryIndex()`。在“我的 > 本地媒体库”加入带 `video_file_outlined` 图标的“媒体识别”入口。

- [ ] **Step 6: 运行 UI、控制器和导航测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\media_recognition_settings_ui_test.dart test\cloud_library_controller_test.dart test\navigation_config_test.dart`

Expected: PASS。

- [ ] **Step 7: 运行代码生成并提交界面接入**

Run: `D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`

Expected: exit 0；若 MobX 生成文件无实际变化，不提交无关生成文件。

```powershell
git add -- lib/pages/settings/media_recognition_settings.dart lib/pages/settings/settings_module.dart lib/pages/my/my_page.dart lib/pages/index_module.dart lib/providers/cloud_library_controller.dart test/media_recognition_settings_ui_test.dart test/cloud_library_controller_test.dart test/navigation_config_test.dart
git commit -m "添加媒体识别限制设置界面"
```

### Task 5: 更新发布版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`

- [ ] **Step 1: 先更新版本契约测试的当前版本期望**

将本次版本定为 `2.0.8+20008`，MSIX 版本为 `2.0.8.0`。保持现有一致性测试，并补充当前版本发布文案必须同时包含“本地媒体库”“网盘媒体库”“文件大小限制”。

- [ ] **Step 2: 运行版本测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，当前仍为 2.0.7 且缺少新文案。

- [ ] **Step 3: 更新版本和面向用户的发布说明**

更新全部版本来源，并在发布说明和版本历史首项写明：

```text
- 新增媒体识别设置，可分别调整本地媒体库和网盘媒体库识别视频时采用的最小文件大小。
- 支持常用大小预设和自定义限制，保存后可选择立即重新扫描对应媒体来源。
```

- [ ] **Step 4: 运行版本测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交发布元数据**

```powershell
git add -- pubspec.yaml lib/request/config/api_endpoints.dart UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/version_consistency_test.dart
git commit -m "更新二点零点八版本说明"
```

### Task 6: 完整验证、Windows 构建与 MSIX 交付

**Files:**
- Verify: all changed files
- Output: `%USERPROFILE%\Desktop\看影音-2.0.8.msix`

- [ ] **Step 1: 检查本轮状态与关键差异**

Run: `git status --short`

Run: `git diff --check HEAD~5..HEAD`

Expected: 无空白错误，只有本功能与发布相关文件。

- [ ] **Step 2: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: exit 0，全部测试通过。

- [ ] **Step 3: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: exit 0，无 error。

- [ ] **Step 4: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release`

Expected: exit 0，生成 `build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 5: 生成并验证 MSIX**

Run: `D:\flutter\bin\flutter.bat pub run msix:create`

Expected: exit 0，生成 MSIX。展开或读取清单确认 `Identity Version="2.0.8.0"` 且包标识为 `com.kanyingyin.player`。

- [ ] **Step 6: 复制安装包到桌面并验证哈希**

将生成的包复制为 `%USERPROFILE%\Desktop\看影音-2.0.8.msix`，运行：

```powershell
Get-Item -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.0.8.msix"
Get-FileHash -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.0.8.msix" -Algorithm SHA256
```

Expected: 文件存在、大小大于零并输出 SHA256。

- [ ] **Step 7: 最终检查并提交任何必要的交付文件**

Run: `git status --short`

若构建未产生应提交的本轮文件，工作区应干净；若有必要的相关变更，检查关键 diff 后单独提交，禁止加入构建产物或无关文件。
