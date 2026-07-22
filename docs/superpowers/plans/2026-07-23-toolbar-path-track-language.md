# 工具栏、路径输入与轨道语言确认 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除媒体库顶部重复的海报入口，展开三个媒体操作，增加紧凑文件夹地址输入，并让所有内嵌音轨与字幕最终显示明确语言。

**Architecture:** `LibraryPathBar` 只负责展示和编辑状态，文件系统校验继续留在 `LocalPage`/`LocalController`。轨道语言拆为纯模型识别、Hive 偏好服务和播放器确认 UI 三层；控制器用媒体 revision 保护异步确认，播放器表现层只负责弹窗，不改变切轨与退出顺序。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、MobX、Hive CE、media_kit、crypto、flutter_test、Windows MSIX。

---

## 文件结构

- Modify: `lib/features/library/presentation/library_path_bar.dart` — 展开媒体操作并承载紧凑地址输入组件。
- Modify: `lib/pages/local/local_page.dart` — 校验并提交手动文件夹路径。
- Modify: `test/library_presentation_components_test.dart` — 工具栏、宽度、地址输入和回调回归测试。
- Create: `lib/pages/player/models/embedded_track_language.dart` — 语言值对象、常见代码/别名和自动识别。
- Modify: `lib/pages/player/models/embedded_track_info.dart` — 分离内部未解析状态与用户可见标签。
- Create: `lib/features/player/application/embedded_track_language_preferences.dart` — 哈希指纹与 Hive 持久化。
- Create: `lib/pages/player/widgets/track_language_confirmation_dialog.dart` — 一次性多轨道语言确认。
- Modify: `lib/pages/player/player_controller.dart` — 加载覆盖、暂停默认选轨、提交确认和 revision 防护。
- Modify: `lib/pages/player/player_controller.g.dart` — 由 build_runner 重新生成 MobX 代码。
- Modify: `lib/pages/player/player_item.dart` — 监听待确认 revision 并安全显示对话框。
- Modify: `lib/pages/index_module.dart` — 注入轨道语言偏好服务。
- Modify: `lib/utils/storage.dart` — 新增设置键。
- Modify: `test/embedded_track_info_test.dart` — 自动识别和禁止未知文案。
- Create: `test/embedded_track_language_preferences_test.dart` — 指纹、持久化和损坏记录。
- Create: `test/track_language_confirmation_dialog_test.dart` — 强制选择、自定义语言和提交。
- Modify: `test/local_video_controller_test.dart` — 播放器集成和退出保护源码契约。
- Modify: 版本与发布文件 — 发布 2.1.42。

### Task 1: 移除顶部海报入口并展开媒体操作

**Files:**
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/features/library/presentation/library_path_bar.dart`
- Modify: `lib/pages/local/local_page.dart`

- [ ] **Step 1: 编写顶部动作失败测试**

将 `LibraryPathBar` 的现有“显示路径工具、排序和搜索”测试改为直接按钮契约：

```dart
expect(find.byTooltip('更多媒体操作'), findsNothing);
expect(find.text('获取海报'), findsNothing);
expect(find.byTooltip('读取媒体信息'), findsOneWidget);
expect(find.byTooltip('生成缩略图'), findsOneWidget);
expect(find.byTooltip('匹配影片信息'), findsOneWidget);

await tester.tap(find.byTooltip('读取媒体信息'));
await tester.tap(find.byTooltip('生成缩略图'));
await tester.tap(find.byTooltip('匹配影片信息'));
await tester.pump();

expect(fetchedMediaInfo, isTrue);
expect(generatedThumbnails, isTrue);
expect(matchedMetadata, isTrue);
```

再增加忙碌状态测试，分别构造 `isFetchingMediaInfo`、`isFetchingThumbnails`、`isMatchingMetadata`，断言对应 Tooltip 下出现 `CircularProgressIndicator`，其他按钮仍为普通图标。

- [ ] **Step 2: 运行测试确认 RED**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart --plain-name "LibraryPathBar 显示路径工具、排序和搜索，并转发动作"
```

Expected: FAIL，因为当前仍存在“更多媒体操作”，三个动作没有直接渲染。

- [ ] **Step 3: 用三个独立按钮替换弹出菜单**

在 `LibraryPathBar` 中删除 `_LibrarySecondaryAction`、`_secondaryMenuItem`、`_handleSecondaryAction` 和 `PopupMenuButton`。新增忙碌按钮辅助方法：

```dart
Widget _progressButton(
  BuildContext context,
  IconData icon,
  String tooltip,
  bool busy,
  FutureOr<void> Function()? onPressed,
) {
  if (!busy) return _button(context, icon, tooltip, onPressed);
  return Tooltip(
    message: tooltip,
    child: SizedBox.square(
      dimension: 32,
      child: IconButton(
        onPressed: null,
        icon: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}
```

在上级目录按钮前按固定顺序插入：

```dart
_progressButton(
  context,
  Icons.info_outline,
  '读取媒体信息',
  data.isFetchingMediaInfo,
  data.canReadMediaInfo ? onFetchMediaInfo : null,
),
_progressButton(
  context,
  Icons.photo_camera_outlined,
  '生成缩略图',
  data.isFetchingThumbnails,
  data.canGenerateThumbnails ? onGenerateThumbnails : null,
),
_progressButton(
  context,
  Icons.cloud_sync_outlined,
  '匹配影片信息',
  data.isMatchingMetadata,
  data.canMatchMetadata ? onMatchMetadata : null,
),
```

从 `LibraryPathBar` 构造参数中移除 `onFetchPosters`，从 `LocalPage` 组合处移除 `onFetchPosters: () => _fetchPosters(context)`，删除已经没有调用者的 `_fetchPosters` 页面私有方法。保留 `LocalController.fetchPosters`、`_fetchPosterForGroup` 和单卡片封面入口。

- [ ] **Step 4: 运行组件测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\features\library\presentation\library_path_bar.dart lib\pages\local\local_page.dart test\library_presentation_components_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart
```

Expected: LibraryPathBar 与经典海报卡相关测试全部通过。

- [ ] **Step 5: 提交顶部动作改动**

```powershell
git add lib\features\library\presentation\library_path_bar.dart lib\pages\local\local_page.dart test\library_presentation_components_test.dart
git commit -m "展开媒体库常用操作"
```

### Task 2: 增加紧凑文件夹地址输入

**Files:**
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/features/library/presentation/library_path_bar.dart`
- Modify: `lib/pages/local/local_page.dart`

- [ ] **Step 1: 编写地址规范化和输入失败测试**

增加纯函数测试：

```dart
test('媒体库地址去除空白和成对双引号', () {
  expect(normalizeLibraryPathAddress(r'  D:\媒体  '), r'D:\媒体');
  expect(normalizeLibraryPathAddress(r'"D:\媒体"'), r'D:\媒体');
  expect(normalizeLibraryPathAddress(r'  "\\NAS\动画"  '), r'\\NAS\动画');
  expect(normalizeLibraryPathAddress(r'"D:\媒体'), r'"D:\媒体');
});
```

给 `pumpPathBar` 增加 `currentPath` 和 `onPathSubmitted`，再增加 Widget 测试：

```dart
testWidgets('紧凑地址框按 Enter 跳转并显示失败错误', (tester) async {
  var submitted = '';
  var shouldFail = false;
  await pumpPathBar(
    tester,
    width: 900,
    currentPath: r'D:\a TV\动画',
    onPathSubmitted: (path) async {
      submitted = path;
      return shouldFail ? '目录不存在或无法访问' : null;
    },
  );

  final field = find.byKey(const ValueKey('library-path-address'));
  expect(field, findsOneWidget);
  expect(tester.getSize(field).width, lessThanOrEqualTo(250));

  await tester.enterText(field, r' "E:\新目录" ');
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pumpAndSettle();
  expect(submitted, r'E:\新目录');

  shouldFail = true;
  await tester.enterText(field, r'Z:\不存在');
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pumpAndSettle();
  expect(find.text('目录不存在或无法访问'), findsOneWidget);
  expect(find.text(r'Z:\不存在'), findsOneWidget);
});
```

在 1280、900、640px 循环中继续断言 `tester.takeException()` 为 null，并断言三个媒体操作 Tooltip 始终存在。

- [ ] **Step 2: 运行测试确认 RED**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart --plain-name "LibraryPathBar 紧凑地址框按 Enter 跳转并显示失败错误"
```

Expected: FAIL，因为地址字段和 `normalizeLibraryPathAddress` 尚不存在。

- [ ] **Step 3: 实现无文件系统依赖的地址组件**

在 `library_path_bar.dart` 增加：

```dart
typedef LibraryPathSubmit = Future<String?> Function(String path);

String normalizeLibraryPathAddress(String value) {
  var normalized = value.trim();
  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}
```

为 `LibraryPathBarViewData` 增加 `currentPath`，为 `LibraryPathBar` 增加必需回调 `onPathSubmitted`。新增私有 `_LibraryPathAddressField` StatefulWidget，状态字段固定为：

```dart
late final TextEditingController _controller;
late final FocusNode _focusNode;
String? _error;
bool _submitting = false;
int _submissionGeneration = 0;
```

提交逻辑：

```dart
Future<void> _submit() async {
  final path = normalizeLibraryPathAddress(_controller.text);
  if (path.isEmpty) {
    setState(() => _error = '请输入文件夹地址');
    return;
  }
  final generation = ++_submissionGeneration;
  setState(() {
    _submitting = true;
    _error = null;
  });
  final error = await widget.onSubmitted(path);
  if (!mounted || generation != _submissionGeneration) return;
  setState(() {
    _submitting = false;
    _error = error;
    if (error == null) _controller.text = path;
  });
}
```

`didUpdateWidget` 在 `oldWidget.currentPath != widget.currentPath` 时同步已验证路径并把 selection 放到末尾；普通 MobX 重建不能覆盖用户正在输入但尚未提交的文本。字段使用 `TextInputAction.go`、`ValueKey('library-path-address')`、文件夹前缀图标和尾部回车图标。外层使用 `ConstrainedBox(constraints: BoxConstraints(minWidth: 145, maxWidth: 250))`，替换原 `_breadcrumbs` 的 `Expanded`。

- [ ] **Step 4: 在 LocalPage 校验并提交文件夹路径**

新增：

```dart
Future<String?> _submitDirectoryAddress(String rawPath) async {
  final path = normalizeLibraryPathAddress(rawPath);
  if (path.isEmpty) return '请输入文件夹地址';
  try {
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type == FileSystemEntityType.file) return '请输入文件夹地址';
    if (type != FileSystemEntityType.directory) return '目录不存在或无法访问';
  } on FileSystemException {
    return '目录不存在或无法访问';
  }
  await _enterDirectory(path);
  return localController.currentPath == path ? null : '目录不存在或无法访问';
}
```

在 `_pathBarData()` 传入 `currentPath: localController.currentPath`，在 `LibraryPathBar` 传入 `onPathSubmitted: _submitDirectoryAddress`。失败时 `navigateTo` 不会被调用，因此当前列表和路径不变。

- [ ] **Step 5: 运行宽度与地址测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\features\library\presentation\library_path_bar.dart lib\pages\local\local_page.dart test\library_presentation_components_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\desktop_shell_test.dart
```

Expected: 地址规范化、提交错误和三种宽度测试全部通过，无 RenderFlex overflow。

- [ ] **Step 6: 提交地址输入**

```powershell
git add lib\features\library\presentation\library_path_bar.dart lib\pages\local\local_page.dart test\library_presentation_components_test.dart
git commit -m "支持从媒体库输入文件夹地址"
```

### Task 3: 建立可解析且不暴露未知文案的语言模型

**Files:**
- Create: `lib/pages/player/models/embedded_track_language.dart`
- Modify: `lib/pages/player/models/embedded_track_info.dart`
- Modify: `test/embedded_track_info_test.dart`

- [ ] **Step 1: 编写语言代码、标题和未解析标签失败测试**

增加：

```dart
test('识别日语韩语与常见 ISO BCP47 代码', () {
  expect(trackLanguageFromMetadata('ja-JP', '',
      type: EmbeddedTrackType.subtitle).label, '日语');
  expect(trackLanguageFromMetadata('jpn', '',
      type: EmbeddedTrackType.subtitle).label, '日语');
  expect(trackLanguageFromMetadata('ko', '',
      type: EmbeddedTrackType.subtitle).label, '韩语');
  expect(trackLanguageFromMetadata('fra', '',
      type: EmbeddedTrackType.audio).label, '法语');
  expect(trackLanguageFromMetadata('', 'Japanese Commentary',
      type: EmbeddedTrackType.audio).label, '日语');
});

test('未解析轨道只显示类型编号且绝不显示未知语种', () {
  final subtitle =
      EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('7', null, null));
  final audio = EmbeddedTrackInfo.fromAudio(const AudioTrack('3', null, null));
  expect(subtitle.isLanguageResolved, isFalse);
  expect(subtitle.primaryLabel, '字幕轨道 7');
  expect(audio.primaryLabel, '音轨 3');
  expect('${subtitle.primaryLabel} ${subtitle.detailLabel}',
      isNot(contains('未知语种')));
});
```

更新原“未知轨道”测试，不再期待“未知语种”。

- [ ] **Step 2: 运行模型测试确认 RED**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\embedded_track_info_test.dart
```

Expected: FAIL，因为新语言模型、日语/韩语映射和 `isLanguageResolved` 尚不存在。

- [ ] **Step 3: 实现语言值对象与明确匹配**

创建 `embedded_track_language.dart`，公开以下类型：

```dart
enum TrackLanguageSource { metadata, title, user, unresolved }

class TrackLanguageChoice {
  const TrackLanguageChoice({
    required this.code,
    required this.label,
    required this.kind,
    required this.source,
  });

  final String code;
  final String label;
  final TrackLanguageKind kind;
  final TrackLanguageSource source;
  bool get isResolved => source != TrackLanguageSource.unresolved;

  TrackLanguageChoice confirmedByUser() => TrackLanguageChoice(
        code: code,
        label: label,
        kind: kind,
        source: TrackLanguageSource.user,
      );
}
```

将 `EmbeddedTrackType` 和 `TrackLanguageKind` 移到该文件，并为后者补充 `japanese`、`korean`、`other`。实现 `trackLanguageFromMetadata(language, title, {required EmbeddedTrackType type})`：先规范化 `zh-CN/chi/zho`、`en/eng`、`ja/jpn`、`ko/kor`、`fr/fra/fre`、`de/deu/ger`、`es/spa`、`pt/por`、`ru/rus`、`it/ita`、`ar/ara`、`th/tha`、`vi/vie`，再匹配现有中文方言和标题别名；没有明确命中时返回 `source: unresolved`，不猜测。

同一文件定义 revision 保护状态，供控制器和纯单元测试复用：

```dart
class PendingTrackLanguage {
  const PendingTrackLanguage({
    required this.fingerprint,
    required this.type,
    required this.trackId,
    required this.codecLabel,
    required this.title,
  });

  final String fingerprint;
  final EmbeddedTrackType type;
  final String trackId;
  final String codecLabel;
  final String title;
}

class TrackLanguageConfirmationState {
  int _revision = 0;
  String _mediaKey = '';

  int begin(String mediaKey, List<PendingTrackLanguage> pending) {
    _mediaKey = mediaKey;
    return ++_revision;
  }

  bool canApply(int revision, String mediaKey) =>
      revision == _revision && mediaKey == _mediaKey;

  void reset() {
    _mediaKey = '';
    _revision++;
  }
}
```

提供 `commonTrackLanguageChoices`，包含上述语言以及简体中文、繁体中文、简繁双语、国语、粤语、台配。

- [ ] **Step 4: 让 EmbeddedTrackInfo 使用独立语言描述**

为 `EmbeddedTrackInfo` 增加：

```dart
final TrackLanguageChoice language;
final String originalCodec;
bool get isLanguageResolved => language.isResolved;

EmbeddedTrackInfo withLanguage(TrackLanguageChoice value) => EmbeddedTrackInfo(
  id: id,
  type: type,
  kind: value.kind,
  language: value,
  primaryLabel: value.isResolved
      ? value.label
      : '${type == EmbeddedTrackType.subtitle ? '字幕' : '音轨'}轨道 $id',
  detailLabel: detailLabel,
  originalTitle: originalTitle,
  originalCodec: originalCodec,
);
```

工厂方法只把明确匹配结果用作语言主标题；未解析时主标题固定为“字幕轨道 N”或“音轨 N”。轨道标题、编码和声道继续进入详情行。

- [ ] **Step 5: 运行语言模型测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\pages\player\models\embedded_track_language.dart lib\pages\player\models\embedded_track_info.dart test\embedded_track_info_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\embedded_track_info_test.dart test\player_embedded_track_state_test.dart
```

Expected: 自动识别、未解析安全标签和既有选轨优先级全部通过。

- [ ] **Step 6: 提交语言模型**

```powershell
git add lib\pages\player\models\embedded_track_language.dart lib\pages\player\models\embedded_track_info.dart test\embedded_track_info_test.dart
git commit -m "完善内嵌轨道语言识别"
```

### Task 4: 持久化用户确认且隐藏媒体路径

**Files:**
- Create: `lib/features/player/application/embedded_track_language_preferences.dart`
- Modify: `lib/utils/storage.dart`
- Create: `test/embedded_track_language_preferences_test.dart`

- [ ] **Step 1: 编写指纹和偏好失败测试**

使用测试 Hive box 构造服务：

```dart
test('轨道语言指纹稳定且不包含原始路径', () {
  final key = embeddedTrackLanguageFingerprint(
    mediaKey: r'D:\私密\电影.mkv',
    type: EmbeddedTrackType.subtitle,
    trackId: '1',
    codec: 'ass',
    title: '简中',
  );
  expect(key, hasLength(64));
  expect(key, isNot(contains('私密')));
  expect(key, embeddedTrackLanguageFingerprint(
    mediaKey: r'D:\私密\电影.mkv',
    type: EmbeddedTrackType.subtitle,
    trackId: '1',
    codec: 'ass',
    title: '简中',
  ));
});

test('保存加载自定义语言并忽略损坏记录', () async {
  final preferences = EmbeddedTrackLanguagePreferences(storage: box);
  const choice = TrackLanguageChoice(
    code: 'custom:elvish',
    label: '精灵语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.user,
  );
  await preferences.save('fingerprint', choice);
  expect(preferences.load('fingerprint')?.label, '精灵语');
  await box.put(SettingBoxKey.embeddedTrackLanguageOverrides,
      <String, Object?>{'broken': 1});
  expect(preferences.load('broken'), isNull);
});
```

- [ ] **Step 2: 运行偏好测试确认 RED**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\embedded_track_language_preferences_test.dart
```

Expected: FAIL，因为指纹函数、设置键和偏好服务尚不存在。

- [ ] **Step 3: 实现哈希指纹和 Hive Map 存储**

在 `SettingBoxKey` 增加：

```dart
embeddedTrackLanguageOverrides = 'embeddedTrackLanguageOverrides',
```

新服务使用 `sha256.convert(utf8.encode(parts.join('\u0000'))).toString()` 生成 64 位键。存储结构固定为：

```dart
<String, Object?>{
  fingerprint: <String, Object?>{
    'code': choice.code,
    'label': choice.label,
    'kind': choice.kind.name,
    'confirmedAt': DateTime.now().toUtc().toIso8601String(),
  },
}
```

`load` 仅接受非空 `code/label` 和可解析 `kind`；其他记录返回 null。`save` 复制现有 Map 后整体写回，避免修改 Hive 返回的动态 Map。

- [ ] **Step 4: 运行偏好测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\features\player\application\embedded_track_language_preferences.dart lib\utils\storage.dart test\embedded_track_language_preferences_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\embedded_track_language_preferences_test.dart test\subtitle_preferences_test.dart
```

Expected: 指纹、保存、加载、损坏回退及既有字幕设置测试全部通过。

- [ ] **Step 5: 提交偏好服务**

```powershell
git add lib\features\player\application\embedded_track_language_preferences.dart lib\utils\storage.dart test\embedded_track_language_preferences_test.dart
git commit -m "记住用户确认的轨道语言"
```

### Task 5: 创建强制完成的轨道语言确认框

**Files:**
- Create: `lib/pages/player/widgets/track_language_confirmation_dialog.dart`
- Create: `test/track_language_confirmation_dialog_test.dart`

- [ ] **Step 1: 编写确认框失败测试**

定义两个待确认轨道并断言：

```dart
await tester.pumpWidget(MaterialApp(
  home: Scaffold(
    body: TrackLanguageConfirmationDialog(
      tracks: const [
        PendingTrackLanguage(
          fingerprint: 'sub-1',
          type: EmbeddedTrackType.subtitle,
          trackId: '1',
          codecLabel: 'PGS',
          title: '',
        ),
        PendingTrackLanguage(
          fingerprint: 'audio-2',
          type: EmbeddedTrackType.audio,
          trackId: '2',
          codecLabel: 'AAC',
          title: 'Commentary',
        ),
      ],
      onConfirm: (values) async => submitted = values,
    ),
  ),
));

expect(find.text('确认轨道语言'), findsOneWidget);
expect(find.text('字幕轨道 1'), findsOneWidget);
expect(find.text('音轨 2'), findsOneWidget);
expect(find.textContaining('未知语种'), findsNothing);
expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存并继续')).onPressed,
    isNull);
```

随后输入“日语”和自定义“精灵语”，断言按钮启用、提交 Map 包含两个 fingerprint，且自定义项使用 `custom:` code。

- [ ] **Step 2: 运行确认框测试确认 RED**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\track_language_confirmation_dialog_test.dart
```

Expected: FAIL，因为确认框尚不存在。

- [ ] **Step 3: 实现可搜索并支持自定义语言的对话框**

使用 Task 3 已定义的 `PendingTrackLanguage` 创建 `TrackLanguageConfirmationDialog` StatefulWidget，每条轨道使用 `Autocomplete<TrackLanguageChoice>`：

```dart
class TrackLanguageConfirmationDialog extends StatefulWidget {
  const TrackLanguageConfirmationDialog({
    super.key,
    required this.tracks,
    required this.onConfirm,
  });

  final List<PendingTrackLanguage> tracks;
  final Future<String?> Function(Map<String, TrackLanguageChoice> choices)
      onConfirm;

  @override
  State<TrackLanguageConfirmationDialog> createState() =>
      _TrackLanguageConfirmationDialogState();
}

optionsBuilder: (value) {
  final query = value.text.trim().toLowerCase();
  if (query.isEmpty) return commonTrackLanguageChoices;
  return commonTrackLanguageChoices.where((choice) =>
      choice.label.toLowerCase().contains(query) ||
      choice.code.toLowerCase().contains(query));
},
onSelected: (choice) => _setChoice(track.fingerprint, choice),
```

输入文字未命中列表时，在失焦或提交时构造：

```dart
TrackLanguageChoice(
  code: 'custom:${Uri.encodeComponent(text)}',
  label: text,
  kind: TrackLanguageKind.other,
  source: TrackLanguageSource.user,
)
```

只有 `_choices.length == widget.tracks.length` 时启用“保存并继续”。提交期间禁用全部输入并显示进度环。`onConfirm` 返回的非空字符串视为可继续播放的持久化警告，使用 `Navigator.pop(context, warning)` 关闭并交给播放器页面提示；只有回调抛出异常时才在对话框底部显示“保存失败，请重试”且不关闭。

- [ ] **Step 4: 运行确认框测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\pages\player\models\embedded_track_language.dart lib\pages\player\widgets\track_language_confirmation_dialog.dart test\track_language_confirmation_dialog_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\track_language_confirmation_dialog_test.dart test\embedded_track_info_test.dart
```

Expected: 必填、搜索、自定义、提交失败和禁止未知文案测试全部通过。

- [ ] **Step 5: 提交确认 UI**

```powershell
git add lib\pages\player\models\embedded_track_language.dart lib\pages\player\widgets\track_language_confirmation_dialog.dart test\track_language_confirmation_dialog_test.dart
git commit -m "增加轨道语言首次确认"
```

### Task 6: 接入播放器并保护退出与媒体切换

**Files:**
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_controller.g.dart`
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `test/local_video_controller_test.dart`
- Modify: `test/player_embedded_track_state_test.dart`

- [ ] **Step 1: 编写 revision 和播放器集成失败测试**

在 `player_embedded_track_state_test.dart` 增加纯状态测试：

```dart
test('轨道语言确认只接受当前媒体 revision', () {
  final state = TrackLanguageConfirmationState();
  final first = state.begin('media-a', const []);
  final second = state.begin('media-b', const []);
  expect(state.canApply(first, 'media-a'), isFalse);
  expect(state.canApply(second, 'media-b'), isTrue);
  state.reset();
  expect(state.canApply(second, 'media-b'), isFalse);
});
```

在 `local_video_controller_test.dart` 增加源码契约：

```dart
expect(source, contains('pendingTrackLanguages'));
expect(source, contains('trackLanguageConfirmationRevision'));
expect(source, contains('_trackLanguageConfirmationState.canApply'));
expect(source, contains('if (!_canUsePlayer) return;'));
expect(source, contains('_trackLanguageConfirmationListener()'));
expect(source, contains('barrierDismissible: false'));
```

- [ ] **Step 2: 运行集成测试确认 RED**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\player_embedded_track_state_test.dart test\local_video_controller_test.dart
```

Expected: FAIL，因为确认状态、观察字段和播放器监听尚不存在。

- [ ] **Step 3: 在控制器解析已保存语言并暂停默认选轨**

为 `PlayerController` 构造函数注入 `EmbeddedTrackLanguagePreferences`，默认值为正式服务。新增：

```dart
_PlayerController({
  SubtitlePreferences? subtitlePreferences,
  EmbeddedTrackLanguagePreferences? trackLanguagePreferences,
  TrueHdFallbackPolicy? trueHdFallbackPolicy,
  ShadersController? shadersController,
})  : _subtitlePreferences = subtitlePreferences ?? SubtitlePreferences(),
      _trackLanguagePreferences = trackLanguagePreferences ??
          EmbeddedTrackLanguagePreferences(),
      _trueHdFallbackPolicy =
          trueHdFallbackPolicy ?? const TrueHdFallbackPolicy(),
      shadersController =
          shadersController ?? Modular.get<ShadersController>();

final EmbeddedTrackLanguagePreferences _trackLanguagePreferences;

@observable
ObservableList<PendingTrackLanguage> pendingTrackLanguages =
    ObservableList<PendingTrackLanguage>();

@observable
int trackLanguageConfirmationRevision = 0;

final TrackLanguageConfirmationState _trackLanguageConfirmationState =
    TrackLanguageConfirmationState();
```

媒体键优先使用 `_lastInitParams?.stableMediaKey`，其次 `_subtitleStorageKey`，最后使用本地 `videoUrl`；只把该值传给哈希函数：

```dart
String _currentTrackLanguageMediaKey() {
  final stable = _lastInitParams?.stableMediaKey?.trim();
  if (stable != null && stable.isNotEmpty) return stable;
  final subtitleKey = _subtitleStorageKey?.trim();
  if (subtitleKey != null && subtitleKey.isNotEmpty) return subtitleKey;
  return videoUrl.trim();
}

String _fingerprintForTrack(String mediaKey, EmbeddedTrackInfo track) =>
    embeddedTrackLanguageFingerprint(
      mediaKey: mediaKey,
      type: track.type,
      trackId: track.id,
      codec: track.originalCodec,
      title: track.originalTitle,
    );
```

`_updateEmbeddedTracks` 先构造原始 `EmbeddedTrackInfo`，再按相同指纹加载偏好：

```dart
EmbeddedTrackInfo applyStoredLanguage(
  String mediaKey,
  EmbeddedTrackInfo track,
) {
  final fingerprint = _fingerprintForTrack(mediaKey, track);
  final stored = _trackLanguagePreferences.load(fingerprint);
  return stored == null ? track : track.withLanguage(stored);
}

PendingTrackLanguage pendingFor(
  String mediaKey,
  EmbeddedTrackInfo track,
) => PendingTrackLanguage(
      fingerprint: _fingerprintForTrack(mediaKey, track),
      type: track.type,
      trackId: track.id,
      codecLabel: track.originalCodec,
      title: track.originalTitle,
    );
```

把未解析项放入 `pendingTrackLanguages`；列表非空时调用 `begin(mediaKey, pending)` 并把返回值赋给 `trackLanguageConfirmationRevision`，列表为空时不触发确认。

在 `_selectDefaultEmbeddedTracks` 开头增加：

```dart
if (pendingTrackLanguages.isNotEmpty) return;
```

这样语言确认前不会自动选择错误轨道。

- [ ] **Step 4: 实现受 revision 保护的确认提交**

新增 MobX action：

```dart
@action
Future<String?> confirmTrackLanguages(
  int revision,
  Map<String, TrackLanguageChoice> choices,
) async {
  final mediaKey = _currentTrackLanguageMediaKey();
  if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) return null;
  try {
    for (final pending in pendingTrackLanguages) {
      final choice = choices[pending.fingerprint];
      if (choice == null) return '请为每条轨道选择语言';
      await _trackLanguagePreferences.save(
        pending.fingerprint,
        choice.confirmedByUser(),
      );
      if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
        return null;
      }
    }
    _applyConfirmedTrackLanguages(mediaKey, choices);
    pendingTrackLanguages.clear();
    await _selectDefaultEmbeddedTracks();
    return null;
  } on Object {
    if (!_trackLanguageConfirmationState.canApply(revision, mediaKey)) {
      return null;
    }
    _applyConfirmedTrackLanguages(mediaKey, choices);
    pendingTrackLanguages.clear();
    await _selectDefaultEmbeddedTracks();
    return '语言设置未能保存，下次可能需要重新确认';
  }
}
```

同一步实现被上面 action 调用的应用方法，确保没有未定义的集成钩子：

```dart
void _applyConfirmedTrackLanguages(
  String mediaKey,
  Map<String, TrackLanguageChoice> choices,
) {
  EmbeddedTrackInfo resolve(EmbeddedTrackInfo track) {
    final choice = choices[_fingerprintForTrack(mediaKey, track)];
    return choice == null ? track : track.withLanguage(choice.confirmedByUser());
  }

  final audio = availableAudioTracks.map(resolve).toList(growable: false);
  final subtitles = availableEmbeddedSubtitleTracks
      .map(resolve)
      .toList(growable: false);
  availableAudioTracks
    ..clear()
    ..addAll(audio);
  availableEmbeddedSubtitleTracks
    ..clear()
    ..addAll(subtitles);
}
```

`_resetEmbeddedTrackState` 必须先 `reset()` 确认状态、递增 revision、清空 pending，再清空轨道列表。每个 await 后继续使用现有播放器可用性和 revision 检查。

- [ ] **Step 5: 在 PlayerItem 安全显示一次确认框**

在 `initState` 增加 MobX reaction：

```dart
_trackLanguageConfirmationListener = mobx.reaction<int>(
  (_) => playerController.trackLanguageConfirmationRevision,
  (revision) => _scheduleTrackLanguageConfirmation(revision),
);
```

调度方法使用 `WidgetsBinding.instance.addPostFrameCallback`，进入前和对话框返回后都检查 `_canUsePlayer`。对话框调用：

```dart
final warning = await showDialog<String?>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TrackLanguageConfirmationDialog(
    tracks: tracks,
    onConfirm: (choices) =>
        playerController.confirmTrackLanguages(revision, choices),
  ),
);
if (!_canUsePlayer) return;
if (warning != null && warning.isNotEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(warning)),
  );
}
```

同一 revision 用 `_shownTrackLanguageRevision` 去重。`dispose` 在释放其他监听前调用 `_trackLanguageConfirmationListener()`；`_stopInteractiveWorkForExit` 会让 `_canUsePlayer` 立即变为 false，旧对话框结果不得继续访问控制器播放器方法。

- [ ] **Step 6: 注册依赖并生成 MobX 代码**

在 `index_module.dart` 注册 `EmbeddedTrackLanguagePreferences`，并在 `PlayerController` 工厂中注入。运行：

```dart
i.addSingleton<SubtitlePreferences>(SubtitlePreferences.new);
i.addSingleton<EmbeddedTrackLanguagePreferences>(
  EmbeddedTrackLanguagePreferences.new,
);
i.addSingleton<TrueHdFallbackPolicy>(TrueHdFallbackPolicy.new);
i.addSingleton<PlayerController>(() => PlayerController(
      subtitlePreferences: Modular.get<SubtitlePreferences>(),
      trackLanguagePreferences:
          Modular.get<EmbeddedTrackLanguagePreferences>(),
      trueHdFallbackPolicy: Modular.get<TrueHdFallbackPolicy>(),
    ));
```

然后运行：

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\cache\dart-sdk\bin\dart.exe run build_runner build --delete-conflicting-outputs
```

Expected: `player_controller.g.dart` 更新 pending/revision atom 与 confirm action，无冲突输出。

- [ ] **Step 7: 运行播放器相关测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\pages\player\player_controller.dart lib\pages\player\player_item.dart lib\pages\index_module.dart test\local_video_controller_test.dart test\player_embedded_track_state_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\embedded_track_info_test.dart test\embedded_track_language_preferences_test.dart test\track_language_confirmation_dialog_test.dart test\player_embedded_track_state_test.dart test\local_video_controller_test.dart test\player_lifecycle_test.dart
```

Expected: 语言识别、持久化、确认 UI、切轨和退出生命周期全部通过。

- [ ] **Step 8: 提交播放器集成**

```powershell
git add lib\pages\player\player_controller.dart lib\pages\player\player_controller.g.dart lib\pages\player\player_item.dart lib\pages\index_module.dart test\local_video_controller_test.dart test\player_embedded_track_state_test.dart
git commit -m "接入轨道语言确认流程"
```

### Task 7: 发布 2.1.42

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 查询并记录当前已安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,Architecture
```

Expected: 明确记录实际结果；计划编写时为 `2.1.41.0 / X64`。

- [ ] **Step 2: 先更新版本测试并确认 RED**

将测试期望改为：

```dart
const expectedVersion = '2.1.42';
const expectedBuildNumber = '20142';
```

运行：

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: FAIL，生产版本仍为 2.1.41。

- [ ] **Step 3: 更新版本源和用户文案**

精确更新：

```text
pubspec.yaml: version: 2.1.42+20142
pubspec.yaml: msix_version: 2.1.42.0
lib/core/app_version.dart: current = '2.1.42'
README.md: | 当前版本 | 2.1.42 |
```

发布文案使用：

```markdown
标题：看影音 2.1.42 测试版

- 媒体库顶部移除重复的“获取海报”入口，读取媒体信息、生成缩略图和匹配影片信息现在可以直接点击。
- 当前文件夹改为紧凑地址框，可直接输入或粘贴盘符与网络文件夹路径，按 Enter 即可跳转；无效地址不会清空当前列表。
- 内嵌音轨与字幕补充常见语言识别；文件没有语言标记时会请你确认一次并保存在本机，菜单不再显示“未知语种”。
- 单部影片获取或更换封面、经典海报墙和原有悬停动画继续保留。
- 播放器退出、切轨、字幕渲染、硬件解码和 Anime4K 行为保持不变。
```

在 `versionHistoryList` 首位加入 2.1.42、日期 `2026-07-23`、`isPrerelease: true` 和同义普通用户文案。

- [ ] **Step 4: 格式化并运行版本测试确认 GREEN**

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: 版本一致性测试全部通过。

- [ ] **Step 5: 提交版本更新**

```powershell
git add pubspec.yaml lib\core\app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib\utils\version_history.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
git commit -m "发布 2.1.42 工具栏与轨道语言优化版"
```

### Task 8: 完整门禁与签名交付

**Files:**
- Verify: all tracked files
- Build: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:/Users/asus/Desktop/看影音-2.1.42.msix`
- Deliver: `C:/Users/asus/Desktop/看影音-2.1.42-异机安装包.zip`

- [ ] **Step 1: 检查格式、差异边界和工作树**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
git diff --check main...HEAD
git diff --exit-code 527b055..HEAD -- lib\features\library\presentation\immersive_media_card.dart lib\features\library\presentation\library_media_grid.dart
git status --short
git -C D:\KanYingYin status --short
```

Expected: 0 格式改动、无空白错误、经典海报墙零差异、两个工作区干净；播放器文件只包含本计划的语言确认和既有退出保护。

- [ ] **Step 2: 串行执行完整测试与静态分析**

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: 全部测试通过，静态分析输出 `No issues found!`。

- [ ] **Step 3: 安全清理测试 APPDATA**

先解析 `D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata` 绝对路径，确认它位于隔离 worktree 内且末级目录严格等于 `.dart_appdata`；只有两项都为 true 才使用 `Remove-Item -LiteralPath ... -Recurse -Force`。再次确认两个工作区状态干净。

- [ ] **Step 4: 运行签名 Release 脚本**

```powershell
Get-Process -Name kanyingyin -ErrorAction SilentlyContinue |
  Where-Object { -not $_.HasExited }
& .\tool\windows\build_signed_release.ps1
```

Expected: Windows Release、MSIX 封装和 SignTool 全部成功，0 warning / 0 error，桌面生成两个 2.1.42 文件。

- [ ] **Step 5: 独立验证交付物**

使用 `Get-AuthenticodeSignature`、`System.IO.Compression.ZipFile` 和 `Get-FileHash` 验证：

```text
SignatureStatus = Valid
SignerSubject = CN=KanYingYin
Thumbprint = A4A2CAA9623FBB8CD27ABC4838D186202EFC1AD6
IdentityName = com.kanyingyin.player
Version = 2.1.42.0
Architecture = x64
构建 MSIX SHA-256 = 桌面 MSIX SHA-256 = ZIP 内 MSIX SHA-256
ZIP 固定文件 = MSIX、看影音.cer、安装看影音.ps1、安装看影音.cmd、安装说明.txt、SHA256.txt
```

- [ ] **Step 6: 最终版本与隔离状态**

再次执行：

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,Architecture
git status --short
git -C D:\KanYingYin status --short
```

记录实际已安装版本；不主动安装。保留 `codex/ui-refresh-v1` 和 `D:\KanYingYin\.worktrees\ui-refresh-v1`，不合并、不删除。
