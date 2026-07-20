# Baidu Filemetas Compatibility and Version Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复百度 `filemetas` 文件名字段差异导致的播放失败，并在“清除缓存”下方展示当前版本，交付 2.1.30 安装包。

**Architecture:** 百度响应解析器按接口区分文件名字段：目录列表严格读取 `server_filename`，文件详情优先读取 `filename` 并兼容 `server_filename`。关于页直接读取 `AppVersion.current`，版本与发布文件统一升级后使用既有私人发布脚本完成签名 MSIX 交付。

**Tech Stack:** Flutter 3.41.9、Dart、flutter_test、card_settings_ui、百度网盘 OpenAPI、Windows MSIX。

---

## 文件结构

- 修改 `test/fixtures/baidu/filemetas_success.json`：以百度实际 `filemetas` 结构保存测试夹具。
- 修改 `test/baidu_response_parser_test.dart`：覆盖 `filename`、旧字段回退和严格拒绝边界。
- 修改 `lib/services/cloud/baidu/baidu_response_parser.dart`：按接口选择文件名字段。
- 修改 `test/about_page_content_test.dart`：验证版本项位于清除缓存之后并读取统一版本常量。
- 修改 `lib/pages/about/about_page.dart`：增加只读“当前版本”设置项。
- 修改版本和用户文案文件：交付 2.1.30。

### Task 1: 用失败测试复现 filemetas 字段差异

**Files:**
- Modify: `test/fixtures/baidu/filemetas_success.json`
- Modify: `test/baidu_response_parser_test.dart`
- Modify: `lib/services/cloud/baidu/baidu_response_parser.dart`

- [ ] **Step 1: 将成功夹具改为实际字段**

把 `filemetas_success.json` 中的文件名字段改为：

```json
"filename": "示例电影.mkv"
```

- [ ] **Step 2: 增加文件详情兼容与严格边界测试**

在“文件详情解析 dlink 并拒绝请求外的 fs_id”中增加：

```dart
expect(details.name, '示例电影.mkv');
```

另增加两个测试：

```dart
test('文件详情兼容旧 server_filename 字段', () {
  final details = parser.parseFileDetails(
    <String, Object?>{
      'errno': 0,
      'list': <Object?>[
        <String, Object?>{
          'fs_id': 1002,
          'path': '/影视/旧响应.mkv',
          'server_filename': '旧响应.mkv',
          'size': 8,
          'isdir': 0,
          'server_mtime': 1700000100,
          'dlink': 'https://download.baidu-fixture.invalid/legacy',
        },
      ],
    },
    expectedFsId: '1002',
  );

  expect(details.name, '旧响应.mkv');
});

test('文件详情缺少两个文件名字段时拒绝响应', () {
  expect(
    () => parser.parseFileDetails(
      <String, Object?>{
        'errno': 0,
        'list': <Object?>[
          <String, Object?>{
            'fs_id': 1002,
            'path': '/影视/无文件名.mkv',
            'size': 8,
            'isdir': 0,
            'server_mtime': 1700000100,
          },
        ],
      },
      expectedFsId: '1002',
    ),
    throwsA(isA<CloudDriveException>().having(
      (error) => error.type,
      'type',
      CloudDriveErrorType.incompatible,
    )),
  );
});
```

- [ ] **Step 3: 运行解析器测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_response_parser_test.dart`

Expected: FAIL，实际 `filename` 夹具被判为 `CloudDriveErrorType.incompatible`。

- [ ] **Step 4: 为条目解析增加显式文件名字段参数**

把 `_parseEntry` 改为：

```dart
BaiduFileEntry _parseEntry(
  Object? value, {
  String nameKey = 'server_filename',
  String? fallbackNameKey,
}) {
  if (value is! Map<Object?, Object?>) {
    throw const CloudDriveException(CloudDriveErrorType.incompatible);
  }
  final json = Map<String, Object?>.from(value);
  final fsId = _integer(json['fs_id']);
  final path = _nonEmptyString(json['path']);
  final name = _nonEmptyString(json[nameKey]) ??
      (fallbackNameKey == null
          ? null
          : _nonEmptyString(json[fallbackNameKey]));
  final size = _integer(json['size']);
  final isDirectory = _integer(json['isdir']);
  final modifiedAt = _integer(json['server_mtime']);
  if (fsId == null ||
      fsId < 0 ||
      path == null ||
      name == null ||
      size == null ||
      size < 0 ||
      (isDirectory != 0 && isDirectory != 1) ||
      modifiedAt == null ||
      modifiedAt < 0) {
    throw const CloudDriveException(CloudDriveErrorType.incompatible);
  }
  return BaiduFileEntry(
    fsId: fsId.toString(),
    path: path,
    name: name,
    size: size,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      modifiedAt * Duration.millisecondsPerSecond,
      isUtc: true,
    ),
    isDirectory: isDirectory == 1,
  );
}
```

文件详情调用改为：

```dart
final entry = _parseEntry(
  value,
  nameKey: 'filename',
  fallbackNameKey: 'server_filename',
);
```

目录分页继续使用现有 `_parseEntry(value)`，因此仍严格要求 `server_filename`。

- [ ] **Step 5: 运行解析器测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_response_parser_test.dart`

Expected: PASS，实际字段、旧字段回退、错误 ID 和畸形响应全部通过。

- [ ] **Step 6: 提交解析兼容修复**

```powershell
git add lib/services/cloud/baidu/baidu_response_parser.dart test/baidu_response_parser_test.dart test/fixtures/baidu/filemetas_success.json
git commit -m "兼容百度文件详情字段"
```

### Task 2: 在清除缓存下方展示当前版本

**Files:**
- Modify: `test/about_page_content_test.dart`
- Modify: `lib/pages/about/about_page.dart`

- [ ] **Step 1: 写版本项来源和顺序测试**

在 `test/about_page_content_test.dart` 增加：

```dart
test('清除缓存下方显示统一的当前版本', () {
  final source = File('lib/pages/about/about_page.dart').readAsStringSync();
  final clearCacheIndex = source.indexOf("'清除缓存'");
  final currentVersionIndex = source.indexOf("'当前版本'");

  expect(clearCacheIndex, greaterThanOrEqualTo(0));
  expect(currentVersionIndex, greaterThan(clearCacheIndex));
  expect(
    source,
    contains("package:kanyingyin/core/app_version.dart"),
  );
  expect(source, contains('AppVersion.current'));
  expect(source, isNot(contains("Text('2.1.30')")));
});
```

- [ ] **Step 2: 运行页面内容测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/about_page_content_test.dart --plain-name "清除缓存下方显示统一的当前版本"`

Expected: FAIL，页面尚无“当前版本”和 `AppVersion.current`。

- [ ] **Step 3: 增加只读版本设置项**

在 `about_page.dart` 导入：

```dart
import 'package:kanyingyin/core/app_version.dart';
```

在“清除缓存”tile 后增加：

```dart
SettingsTile<void>(
  title: Text('当前版本', style: TextStyle(fontFamily: fontFamily)),
  trailing: Text(
    AppVersion.current,
    style: TextStyle(fontFamily: fontFamily),
  ),
),
```

- [ ] **Step 4: 运行页面内容测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/about_page_content_test.dart`

Expected: PASS，版本项位于清除缓存之后且没有页面硬编码版本号。

- [ ] **Step 5: 提交版本展示**

```powershell
git add lib/pages/about/about_page.dart test/about_page_content_test.dart
git commit -m "在关于页显示当前版本"
```

### Task 3: 验证百度播放解析链路

**Files:**
- Verify: `test/baidu_api_client_test.dart`
- Verify: `test/baidu_drive_client_test.dart`
- Verify: `test/baidu_response_parser_test.dart`
- Verify: `test/baidu_range_remote_reader_test.dart`
- Verify: `test/cloud_playback_resolver_test.dart`
- Verify: `test/cloud_range_relay_service_test.dart`

- [ ] **Step 1: 运行百度详情与播放链路测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_response_parser_test.dart test/baidu_api_client_test.dart test/baidu_drive_client_test.dart test/baidu_range_remote_reader_test.dart test/cloud_playback_resolver_test.dart test/cloud_range_relay_service_test.dart`

Expected: 全部 PASS；`filename` 文件详情进入 dlink 解析，目录和本机中转边界保持不变。

- [ ] **Step 2: 检查生产代码不含测试凭据**

Run: `rg -n "access-fixture|refresh-fixture|secret-fixture|download.baidu-fixture.invalid" lib`

Expected: 无输出。

### Task 4: 更新 2.1.30 版本与普通用户文案

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`

- [ ] **Step 1: 先更新版本测试期望**

使用：

```dart
const expectedVersion = '2.1.30';
const expectedBuildNumber = '20130';
```

把 `identity_v2_zero_residue_test.dart` 的当前版本期望和 `version_history_current_test.dart` 的当前版本查询同步改为 `2.1.30`。

- [ ] **Step 2: 运行版本测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart`

Expected: FAIL，生产版本和发布文案仍为 2.1.29。

- [ ] **Step 3: 更新生产版本和 MSIX 版本**

使用以下唯一版本组合：

```text
pubspec version: 2.1.30+20130
MSIX version: 2.1.30.0
AppVersion.current: 2.1.30
```

- [ ] **Step 4: 增加面向普通用户的发布内容**

在版本历史顶部、`RELEASE_NOTES.md` 和 `UPDATE_DIALOG_COPY.md` 使用以下同义内容：

```text
看影音 2.1.30 测试版
- 修复百度网盘视频因文件详情字段差异而无法进入播放器的问题。
- “关于”页面会在“清除缓存”下方显示当前版本，便于确认已安装的安装包。
- 本次不会修改百度网盘文件、目录或本地视频；夸克、OpenList、本地媒体库和播放器其他功能保持可用。
```

把 README 当前版本更新为 `2.1.30`。

- [ ] **Step 5: 运行版本测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart`

Expected: PASS，Dart、pubspec、MSIX、README 和发布文案版本一致。

- [ ] **Step 6: 提交 2.1.30 版本更新**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布二点一三十测试版"
```

### Task 5: 全量质量门禁与 MSIX 交付

**Files:**
- Verify: entire repository
- Output: `C:\Users\asus\Desktop\看影音-2.1.30.msix`
- Output: `C:\Users\asus\Desktop\看影音-2.1.30-异机安装包.zip`

- [ ] **Step 1: 格式化本轮 Dart 文件**

Run: `D:\flutter\bin\dart.bat format lib/services/cloud/baidu/baidu_response_parser.dart test/baidu_response_parser_test.dart lib/pages/about/about_page.dart test/about_page_content_test.dart lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart`

Expected: 格式化成功且文件保持 UTF-8。

- [ ] **Step 2: 检查关键 diff 和工作区边界**

Run: `git status --short` 与 `git diff --check`

Expected: 无空白错误；`.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 保持未暂存，其他变更均属于本轮。

- [ ] **Step 3: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部 PASS。

- [ ] **Step 4: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 5: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `build\windows\x64\runner\Release\kanyingyin.exe` 构建成功。

- [ ] **Step 6: 使用私人发布脚本生成签名安装包**

Run: `powershell -ExecutionPolicy Bypass -File tool\windows\build_private_release.ps1`

Expected: 脚本验证版本和签名，并在桌面生成 `看影音-2.1.30.msix` 与 `看影音-2.1.30-异机安装包.zip`；不得输出内置 TMDB Key 或签名私钥。

- [ ] **Step 7: 验证最终产物**

检查 MSIX 清单应为：

```text
Identity Name: com.kanyingyin.player
Version: 2.1.30.0
Architecture: x64
```

Run: `Get-AuthenticodeSignature 'C:\Users\asus\Desktop\看影音-2.1.30.msix'` 与 `Get-FileHash -Algorithm SHA256 'C:\Users\asus\Desktop\看影音-2.1.30.msix'`

Expected: 签名状态 `Valid`，并记录 SHA-256 供最终交付说明。

- [ ] **Step 8: 提交交付所需的剩余改动**

先运行 `git status --short` 和关键 diff，只暂存本轮相关文件；若前序任务已全部提交且构建未产生需提交文件，则不创建空提交。
