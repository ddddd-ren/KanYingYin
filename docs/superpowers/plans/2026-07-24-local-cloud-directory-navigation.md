# Local and Cloud Directory Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为本地与网盘媒体库增加当前目录子文件夹下拉导航，并把夸克、百度、OpenList 的目录选择页统一为支持地址跳转和多选的应用内界面。

**Architecture:** 使用纯 Dart 的 `CloudDirectoryScopeTree` 从配置根目录和索引路径派生目录范围；使用独立的 `DirectoryAddressDropdown` 复用本地与网盘路径框交互；网盘目录选择器通过强类型加载回调复用统一页面，保留各来源的真实远程 ID、凭据和返回类型。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、Flutter Modular、MobX、flutter_test、path。

---

## 文件结构

- 新建 `lib/features/cloud/application/cloud_directory_scope_tree.dart`：网盘索引目录树、直接子目录和范围判断。
- 新建 `lib/features/cloud/application/cloud_directory_address_resolver.dart`：通过逐级目录加载把输入路径解析为带真实 ID 的远程目录链。
- 新建 `lib/features/library/presentation/directory_address_dropdown.dart`：可编辑地址、异步子目录菜单、加载与错误状态。
- 新建 `lib/pages/cloud/widgets/cloud_directory_picker_page.dart`：统一网盘目录选择页面和单选/多选状态。
- 修改 `lib/features/library/presentation/library_path_bar.dart`：使用通用路径下拉并暴露子目录回调。
- 修改 `lib/pages/local/local_page.dart`：接入本地直接子目录读取。
- 修改 `lib/pages/cloud/resources/cloud_resources_controller.dart`：保存网盘浏览范围并派生范围内集合。
- 修改 `lib/pages/cloud/resources/cloud_resources_page.dart`：增加网盘路径下拉和上级入口。
- 修改三个网盘选择器文件：保留公开类名，适配统一页面。
- 修改对应 Widget、控制器、编辑器和版本测试。

### Task 1: 网盘目录范围纯逻辑

**Files:**
- Create: `lib/features/cloud/application/cloud_directory_scope_tree.dart`
- Create: `test/cloud_directory_scope_tree_test.dart`

- [ ] **Step 1: 写直接子目录和范围边界失败测试**

```dart
test('多根目录只暴露配置根且按路径段过滤子树', () {
  final tree = CloudDirectoryScopeTree.build(
    rootPaths: const ['/影视', '/动漫/季度'],
    mediaPaths: const [
      '/影视/电影/正片.mkv',
      '/影视剧/不应命中.mkv',
      '/动漫/季度/作品/S01E01.mkv',
    ],
  );

  expect(tree.childrenOf(null).map((item) => item.path), ['/动漫/季度', '/影视']);
  expect(tree.childrenOf('/影视').single.path, '/影视/电影');
  expect(tree.contains('/影视/电影/正片.mkv', '/影视'), isTrue);
  expect(tree.contains('/影视剧/不应命中.mkv', '/影视'), isFalse);
  expect(tree.parentOf('/影视/电影'), '/影视');
  expect(tree.parentOf('/影视'), isNull);
});
```

- [ ] **Step 2: 运行测试确认因类型不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_directory_scope_tree_test.dart`

Expected: FAIL，提示 `CloudDirectoryScopeTree` 未定义。

- [ ] **Step 3: 实现规范化、直接子目录、父级和范围判断**

```dart
import 'package:path/path.dart' as p;

class CloudDirectoryScopeItem {
  const CloudDirectoryScopeItem({required this.path, required this.label});
  final String path;
  final String label;
}

class CloudDirectoryScopeTree {
  CloudDirectoryScopeTree._(this._roots, this._directories);

  final List<String> _roots;
  final Set<String> _directories;

  factory CloudDirectoryScopeTree.build({
    required Iterable<String> rootPaths,
    required Iterable<String> mediaPaths,
  }) {
    final roots = rootPaths.map(normalize).toSet().toList()..sort();
    final directories = <String>{...roots};
    for (final mediaPath in mediaPaths) {
      var directory = normalize(p.posix.dirname(normalize(mediaPath)));
      for (final root in roots) {
        if (!_isWithin(directory, root)) continue;
        while (_isWithin(directory, root)) {
          directories.add(directory);
          if (directory == root) break;
          final parent = normalize(p.posix.dirname(directory));
          if (parent == directory) break;
          directory = parent;
        }
        break;
      }
    }
    return CloudDirectoryScopeTree._(roots, directories);
  }

  List<CloudDirectoryScopeItem> childrenOf(String? scopePath) {
    final paths = scopePath == null
        ? _roots
        : _directories
            .where((path) =>
                path != normalize(scopePath) &&
                normalize(p.posix.dirname(path)) == normalize(scopePath))
            .toList();
    return paths
        .map((path) => CloudDirectoryScopeItem(
              path: path,
              label: p.posix.basename(path).isEmpty
                  ? path
                  : p.posix.basename(path),
            ))
        .toList(growable: false)
      ..sort((left, right) =>
          left.label.toLowerCase().compareTo(right.label.toLowerCase()));
  }

  bool contains(String mediaPath, String? scopePath) {
    final media = normalize(mediaPath);
    if (scopePath != null) return _isWithin(media, normalize(scopePath));
    return _roots.any((root) => _isWithin(media, root));
  }

  String? parentOf(String scopePath) {
    final scope = normalize(scopePath);
    final roots = _roots.where((root) => _isWithin(scope, root)).toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    if (roots.isEmpty || roots.first == scope) return null;
    final parent = normalize(p.posix.dirname(scope));
    return _isWithin(parent, roots.first) ? parent : null;
  }

  bool hasDirectory(String path) => _directories.contains(normalize(path));

  static String normalize(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    normalized = p.posix.normalize(normalized);
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool _isWithin(String path, String root) =>
      root == '/' || path == root || path.startsWith('$root/');
}
```

- [ ] **Step 4: 运行目录树测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_directory_scope_tree_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交目录范围逻辑**

```powershell
git add lib/features/cloud/application/cloud_directory_scope_tree.dart test/cloud_directory_scope_tree_test.dart
git commit -m "功能：增加网盘目录范围模型"
```

### Task 2: 通用可编辑路径下拉

**Files:**
- Create: `lib/features/library/presentation/directory_address_dropdown.dart`
- Modify: `lib/features/library/presentation/library_path_bar.dart`
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1: 写路径下拉失败测试**

```dart
testWidgets('路径框下拉直接子文件夹且保留 Enter 跳转', (tester) async {
  String? selected;
  String? submitted;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DirectoryAddressDropdown(
        currentPath: r'D:\TV',
        enabled: true,
        loadChildren: (_) async => const [
          DirectoryNavigationItem(label: '动画', path: r'D:\TV\动画'),
        ],
        onChildSelected: (item) => selected = item.path,
        onSubmitted: (path) async {
          submitted = path;
          return null;
        },
      ),
    ),
  ));

  await tester.tap(find.byTooltip('展开子文件夹'));
  await tester.pumpAndSettle();
  expect(find.text('动画'), findsOneWidget);
  await tester.tap(find.text('动画'));
  expect(selected, r'D:\TV\动画');

  await tester.enterText(find.byKey(const ValueKey('directory-address')), r'E:\Movie');
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pumpAndSettle();
  expect(submitted, r'E:\Movie');
});
```

- [ ] **Step 2: 运行测试确认组件缺失**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/library_presentation_components_test.dart --plain-name "路径框下拉直接子文件夹且保留 Enter 跳转"`

Expected: FAIL，提示 `DirectoryAddressDropdown` 未定义。

- [ ] **Step 3: 实现 `MenuAnchor` 路径下拉组件**

```dart
class DirectoryNavigationItem {
  const DirectoryNavigationItem({
    required this.label,
    required this.path,
    this.subtitle,
  });
  final String label;
  final String path;
  final String? subtitle;
}

class DirectoryAddressDropdown extends StatefulWidget {
  const DirectoryAddressDropdown({
    super.key,
    required this.currentPath,
    required this.enabled,
    required this.loadChildren,
    required this.onChildSelected,
    required this.onSubmitted,
  });
}
```

组件 State 明确定义 `_controller`、`_focusNode`、`_menuController`、`_children`、`_error`、`_loadingChildren`、`_submitting` 和 generation。`_toggleChildren()` 先等待 `loadChildren(currentPath)`，成功后打开 `MenuAnchor`，空列表生成禁用菜单项“没有子文件夹”；异常写入“目录不存在或无法访问”，不改写控制器文本。组件继续使用现有圆角、填充色和紧凑高度。右侧下拉箭头替代跳转箭头，地址提交通过 Enter 完成；加载时右侧显示 16px 进度环。

- [ ] **Step 4: `LibraryPathBar` 增加回调并替换私有地址组件**

```dart
final Future<List<DirectoryNavigationItem>> Function(String path)?
    onLoadChildDirectories;
final FutureOr<void> Function(DirectoryNavigationItem item)?
    onChildDirectorySelected;

DirectoryAddressDropdown(
  currentPath: data.currentPath,
  enabled: !data.isLoading,
  loadChildren: onLoadChildDirectories ?? (_) async => const [],
  onChildSelected: (item) async =>
      await onChildDirectorySelected?.call(item),
  onSubmitted: onPathSubmitted,
)
```

删除 `_LibraryPathAddressField`，保留 `normalizeLibraryPathAddress` 的兼容入口或迁移到新组件并重新导出。

- [ ] **Step 5: 运行路径栏组件测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/library_presentation_components_test.dart`

Expected: PASS，现有动画、工具栏和地址错误测试不回归。

- [ ] **Step 6: 提交通用路径下拉**

```powershell
git add lib/features/library/presentation/directory_address_dropdown.dart lib/features/library/presentation/library_path_bar.dart test/library_presentation_components_test.dart
git commit -m "功能：增加媒体库路径下拉"
```

### Task 3: 本地媒体库接入子目录下拉

**Files:**
- Modify: `lib/pages/local/local_page.dart`
- Modify: `test/local_video_controller_test.dart`
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1: 写本地页面回调组合失败测试**

```dart
test('LocalPage 为路径栏提供本地直接子目录', () {
  final source = File('lib/pages/local/local_page.dart').readAsStringSync();
  expect(source, contains('onLoadChildDirectories: _loadChildDirectories'));
  expect(source, contains('onChildDirectorySelected:'));
  expect(source, contains('loadLocalDirectories(path)'));
});
```

- [ ] **Step 2: 运行测试确认页面尚未接入**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_video_controller_test.dart --plain-name "LocalPage 为路径栏提供本地直接子目录"`

Expected: FAIL，缺少回调组合。

- [ ] **Step 3: 实现本地目录转换并复用现有进入逻辑**

```dart
Future<List<DirectoryNavigationItem>> _loadChildDirectories(String path) async {
  final directories = await loadLocalDirectories(path);
  return directories
      .map((child) => DirectoryNavigationItem(
            label: p.basename(child),
            path: child,
            subtitle: child,
          ))
      .toList(growable: false);
}
```

`LibraryPathBar` 传入 `_loadChildDirectories`；选择目录时调用 `_enterDirectory(item.path)`。不修改本地扫描、媒体卡片或文件删除逻辑。

- [ ] **Step 4: 运行本地路径栏与选择器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_video_controller_test.dart test/local_directory_picker_test.dart test/library_presentation_components_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交本地接入**

```powershell
git add lib/pages/local/local_page.dart test/local_video_controller_test.dart test/library_presentation_components_test.dart
git commit -m "功能：支持本地路径下拉目录"
```

### Task 4: 网盘媒体库目录范围导航

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_controller_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写控制器目录范围失败测试**

```dart
test('选择网盘目录后仅聚合该目录子树并可返回全部根目录', () async {
  final fixture = await _DirectoryScopeFixture.create(const [
    '/影视/电影/A.mkv', '/影视/剧集/B.mkv', '/其他/C.mkv',
  ]);
  final controller = fixture.controller;

  expect(controller.directoryScopeChildren.map((item) => item.path),
      contains('/影视'));
  controller.selectDirectoryScope('/影视/电影');
  expect(controller.visibleIndexedItems.map((item) => item.remotePath),
      ['/影视/电影/A.mkv']);
  controller.navigateDirectoryScopeUp();
  expect(controller.currentDirectoryScope, '/影视');
  controller.clearDirectoryScope();
  expect(controller.visibleIndexedItems, hasLength(3));
});

// _DirectoryScopeFixture 复用本文件的 MemoryCloudSourceStorage、
// MemoryCloudMediaIndexStorage 和 _scopedCloudEpisode 创建真实控制器。
```

- [ ] **Step 2: 运行控制器测试确认范围 API 缺失**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_controller_test.dart --plain-name "选择网盘目录后仅聚合该目录子树并可返回全部根目录"`

Expected: FAIL，目录范围 getter/method 未定义。

- [ ] **Step 3: 在控制器中保存范围并派生可见索引**

```dart
String? currentDirectoryScope;

CloudDirectoryScopeTree get _directoryScopeTree =>
    CloudDirectoryScopeTree.build(
      rootPaths: selectedSource?.remoteRoots.map((root) => root.path) ?? const [],
      mediaPaths: _indexedItems.values.map((item) => item.remotePath),
    );

List<CloudMediaIndexItem> get visibleIndexedItems => _indexedItems.values
    .where((item) => _directoryScopeTree.contains(
          item.remotePath,
          currentDirectoryScope,
        ))
    .toList(growable: false);
```

`collection` 使用 `visibleIndexedItems`，并只保留这些索引项引用的 `CloudWorkIdentity`。来源或快照变更后调用 `_reconcileDirectoryScope()`，范围不存在时回退 `null`。

- [ ] **Step 4: 写并实现网盘路径栏 Widget 测试**

```dart
testWidgets('网盘来源显示目录路径下拉并按选择过滤海报墙', (tester) async {
  final fixture = await _PageFixture.create(
    source: _quarkSource,
    entries: const <CloudFileEntry>[
      CloudFileEntry(id: 'a', remotePath: '/影视/电影/A.mkv', name: '影片 A.mkv', size: 1, modifiedAt: null, isDirectory: false),
      CloudFileEntry(id: 'b', remotePath: '/影视/剧集/B.mkv', name: '剧集 B.mkv', size: 1, modifiedAt: null, isDirectory: false),
    ],
  );
  await tester.pumpWidget(MaterialApp(home: CloudResourcesPage(controller: fixture.controller)));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('cloud-directory-address')), findsOneWidget);
  await tester.tap(find.byTooltip('展开子文件夹'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('电影'));
  await tester.pumpAndSettle();
  expect(find.text('影片 A'), findsOneWidget);
  expect(find.text('剧集 B'), findsNothing);
});
```

在 `_directoryContent` 中用 `DirectoryAddressDropdown` 替换“已汇总全部媒体根目录”静态文字，并保留来源图标、搜索框、进度和海报墙层级。根范围地址显示 `/`，旁边文案显示“全部媒体根目录”；选择和上级调用控制器方法。

- [ ] **Step 5: 运行网盘资源回归测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_controller_test.dart test/cloud_resources_page_test.dart test/cloud_resources_flat_library_test.dart`

Expected: PASS；真实播放远程 ID、字幕引用和 TMDB 匹配测试保持通过。

- [ ] **Step 6: 提交网盘范围导航**

```powershell
git add lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_controller_test.dart test/cloud_resources_page_test.dart
git commit -m "功能：支持网盘媒体库按目录浏览"
```

### Task 5: 统一网盘目录选择页

**Files:**
- Create: `lib/features/cloud/application/cloud_directory_address_resolver.dart`
- Create: `lib/pages/cloud/widgets/cloud_directory_picker_page.dart`
- Modify: `lib/pages/cloud/quark/quark_directory_picker.dart`
- Modify: `lib/pages/cloud/baidu/baidu_directory_picker.dart`
- Modify: `lib/pages/cloud/openlist_directory_picker.dart`
- Modify: `test/quark_source_editor_test.dart`
- Modify: `test/baidu_source_editor_test.dart`
- Modify: `test/cloud_sources_ui_test.dart`
- Create: `test/cloud_directory_picker_page_test.dart`

- [ ] **Step 1: 写远程地址逐级解析失败测试**

```dart
test('夸克和百度地址从根目录逐级解析真实目录 ID', () async {
  final resolver = CloudDirectoryAddressResolver(loader: (directory) async {
    if (directory.path == '/') {
      return const [CloudFileEntry(
        id: 'fid-tv', remotePath: '/影视', name: '影视', size: 0,
        modifiedAt: null, isDirectory: true,
      )];
    }
    return const [CloudFileEntry(
      id: 'fid-show', remotePath: '/影视/剧集', name: '剧集', size: 0,
      modifiedAt: null, isDirectory: true,
    )];
  });

  final result = await resolver.resolve(
    root: const CloudRemoteRef(id: '0', path: '/'),
    targetPath: '/影视/剧集',
  );
  expect(result.current.id, 'fid-show');
  expect(result.ancestry.map((item) => item.id), ['0', 'fid-tv']);
});
```

- [ ] **Step 2: 运行测试确认解析器缺失**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_directory_picker_page_test.dart`

Expected: FAIL，解析器或统一页面未定义。

- [ ] **Step 3: 实现地址解析器**

```dart
typedef CloudDirectoryLoader = Future<List<CloudFileEntry>> Function(
  CloudRemoteRef directory,
);

class CloudDirectoryResolution {
  const CloudDirectoryResolution({
    required this.current,
    required this.ancestry,
  });
  final CloudRemoteRef current;
  final List<CloudRemoteRef> ancestry;
}

class CloudDirectoryAddressResolver {
  const CloudDirectoryAddressResolver({required CloudDirectoryLoader loader})
      : _loader = loader;

  Future<CloudDirectoryResolution> resolve({
    required CloudRemoteRef root,
    required String targetPath,
  }) async {
    final normalizedRoot = CloudDirectoryScopeTree.normalize(root.path);
    final normalizedTarget = CloudDirectoryScopeTree.normalize(targetPath);
    if (normalizedTarget == normalizedRoot) {
      return CloudDirectoryResolution(current: root, ancestry: const []);
    }
    if (normalizedRoot != '/' &&
        !normalizedTarget.startsWith('$normalizedRoot/')) {
      throw const FormatException('目录不存在或无法访问');
    }
    final relative = normalizedRoot == '/'
        ? normalizedTarget.substring(1)
        : normalizedTarget.substring(normalizedRoot.length + 1);
    var current = root;
    var accumulated = normalizedRoot;
    final ancestry = <CloudRemoteRef>[];
    for (final segment in relative.split('/').where((part) => part.isNotEmpty)) {
      final expected = accumulated == '/'
          ? '/$segment'
          : '$accumulated/$segment';
      final entries = await _loader(current);
      final match = entries.where((entry) =>
          entry.isDirectory &&
          CloudDirectoryScopeTree.normalize(entry.remotePath) == expected).firstOrNull;
      if (match == null) {
        throw const FormatException('目录不存在或无法访问');
      }
      ancestry.add(current);
      current = CloudRemoteRef(id: match.id, path: match.remotePath);
      accumulated = expected;
    }
    return CloudDirectoryResolution(
      current: current,
      ancestry: List<CloudRemoteRef>.unmodifiable(ancestry),
    );
  }
}
```

- [ ] **Step 4: 写统一选择页多选与失败保留测试**

```dart
testWidgets('统一网盘选择页支持进入目录、多选和完成数量', (tester) async {
  Future<List<CloudFileEntry>> loader(CloudRemoteRef directory) async =>
      directory.path == '/'
          ? const [CloudFileEntry(id: 'tv', remotePath: '/影视', name: '影视', size: 0, modifiedAt: null, isDirectory: true)]
          : const [];
  await tester.pumpWidget(MaterialApp(
    home: CloudDirectoryPickerPage<List<CloudRemoteRef>>(
      title: '选择网盘目录',
      root: const CloudRemoteRef(id: '0', path: '/'),
      initialSelection: const [],
      loader: loader,
      resultBuilder: (selected) => selected,
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('cloud-directory-address')), findsOneWidget);
  await tester.tap(find.text('影视'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('select-current-directory')));
  await tester.pump();
  expect(find.text('完成（已选 1 个）'), findsOneWidget);
});
```

- [ ] **Step 5: 实现统一选择页**

统一页面维护 `_current`、`_ancestry`、`_directories`、`_selected`、`_loading`、`_addressError` 和 generation。布局严格包含：

```dart
Scaffold(
  appBar: AppBar(
    title: Text(title),
    actions: [TextButton(onPressed: canComplete ? _complete : null, child: Text(completeLabel))],
  ),
  body: Column(children: [
    Row(children: [
      IconButton(tooltip: '上级目录', icon: const Icon(Icons.keyboard_arrow_up_rounded)),
      Expanded(child: TextField(key: const ValueKey('cloud-directory-address'))),
      FilledButton.icon(icon: const Icon(Icons.arrow_forward_rounded), label: const Text('跳转')),
    ]),
    const Divider(height: 1),
    Expanded(child: ListView.builder(/* 文件夹标题进入，复选框选择 */)),
  ]),
)
```

单选模式选择新目录前清空旧选择；多选模式保留所有层级选择。错误只更新 `_addressError` 或 `_errorMessage`，不清空 `_directories` 和 `_selected`。

- [ ] **Step 6: 将三种现有选择器改为共享页面适配器**

```dart
// 夸克/百度：返回 List<CloudRemoteRef>
return CloudDirectoryPickerPage<List<CloudRemoteRef>>(
  title: title,
  root: const CloudRemoteRef(id: '0', path: '/'),
  initialSelection: initialSelection,
  singleSelection: singleSelection,
  loader: (directory) => controller.browseRemoteDirectories(
    source, directory, credential: credential,
  ),
  resultBuilder: (selected) => selected,
);

// OpenList：返回 List<String>
resultBuilder: (selected) =>
    selected.map((item) => item.path).toList(growable: false),
```

OpenList 初始选择由 `source.remoteRoots` 提供。保留原公开构造参数、标题和路由。

- [ ] **Step 7: 运行选择器与编辑器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_directory_picker_page_test.dart test/quark_source_editor_test.dart test/baidu_source_editor_test.dart test/cloud_sources_ui_test.dart test/quark_share_import_page_test.dart`

Expected: PASS。

- [ ] **Step 8: 提交统一网盘目录选择页**

```powershell
git add lib/features/cloud/application/cloud_directory_address_resolver.dart lib/pages/cloud/widgets/cloud_directory_picker_page.dart lib/pages/cloud/quark/quark_directory_picker.dart lib/pages/cloud/baidu/baidu_directory_picker.dart lib/pages/cloud/openlist_directory_picker.dart test/cloud_directory_picker_page_test.dart test/quark_source_editor_test.dart test/baidu_source_editor_test.dart test/cloud_sources_ui_test.dart
git commit -m "功能：统一网盘目录选择页面"
```

### Task 6: 架构约束与全量回归

**Files:**
- Modify: `test/architecture_dependency_test.dart`
- Modify: related tests only when assertions legitimately moved to new files.

- [ ] **Step 1: 增加表现层依赖和旧选择器重复实现检查**

```dart
test('目录导航表现组件不直接依赖控制器和网盘服务', () {
  final source = File(
    'lib/features/library/presentation/directory_address_dropdown.dart',
  ).readAsStringSync();
  expect(source, isNot(contains('flutter_modular')));
  expect(source, isNot(contains('/providers/')));
  expect(source, isNot(contains('/repositories/')));
});
```

- [ ] **Step 2: 格式化本轮 Dart 文件并检查差异**

Run:

```powershell
$dartFiles = git diff --name-only HEAD~5 -- '*.dart'
& D:\flutter\bin\dart.bat format --set-exit-if-changed $dartFiles
git diff --check
```

Expected: format exit 0，`git diff --check` 无输出。

- [ ] **Step 3: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub --reporter compact`

Expected: `All tests passed!`，零失败。

- [ ] **Step 4: 运行全量静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 5: 提交回归约束**

```powershell
git add test/architecture_dependency_test.dart
git commit -m "测试：约束目录导航依赖边界"
```

### Task 7: 版本、Windows Release 与 MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 记录升级前已安装版本**

Run:

```powershell
$pkg = Get-AppxPackage -Name com.kanyingyin.player
if ($null -eq $pkg) { '未安装' } else { $pkg.Version }
```

Expected: 明确输出当前版本或“未安装”，不得从 `pubspec.yaml` 推断。

- [ ] **Step 2: 写 2.1.52 版本一致性失败测试**

将期望更新为：

```dart
const expectedVersion = '2.1.52';
const expectedBuildNumber = '20152';
```

并新增当前版本历史断言，要求文案包含“本地与网盘”“目录下拉”“夸克”“百度”“OpenList”“Windows”“TMDB”“Anime4K”“媒体库”“播放器”“不会修改或删除”和测试版语义。

- [ ] **Step 3: 运行版本测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart`

Expected: FAIL，实际版本仍为 2.1.51。

- [ ] **Step 4: 同步版本与用户文案**

更新：

```yaml
version: 2.1.52+20152
msix_version: 2.1.52.0
```

`AppVersion.current` 改为 `2.1.52`。发布文案说明本地与网盘目录下拉、统一三种网盘选择页、多选保留、离线缓存浏览和不修改原始文件。

- [ ] **Step 5: 运行版本测试、全量测试与分析**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全部 exit 0。

- [ ] **Step 6: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `Built build\windows\x64\runner\Release\kanyingyin.exe`，并核对 `kanyingyin.exe` 与 `data\app.so` 时间戳属于本轮。

- [ ] **Step 7: 生成、签名并复制 MSIX**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected:

- `C:\Users\asus\Desktop\看影音-2.1.52.msix` 存在。
- 清单为 `com.kanyingyin.player / CN=KanYingYin / 2.1.52.0 / x64`。
- `Get-AuthenticodeSignature` 为 `Valid`。
- 桌面包和构建包 SHA-256 一致。

- [ ] **Step 8: 核对安装包和已安装版本**

读取 MSIX 内 `AppxManifest.xml`，再次查询 `Get-AppxPackage -Name com.kanyingyin.player`；如执行了安装，已安装版本必须为 `2.1.52.0`。

- [ ] **Step 9: 最终差异审查与提交**

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart
git add -A
git diff --cached --check
git commit -m "功能：完善本地与网盘目录导航"
```

Expected: 提交后 `git status --short` 为空。
