# 夸克分享转存与媒体扫描联动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户在夸克分享导入页选择转存目录，并保证批量转存成功后只扫描一次且能立即在媒体库看到视频。

**Architecture:** 用纯策略类负责将转存目录合并到来源扫描范围，用历史仓库的原子批量写入保证幂等，再由 `QuarkImportController` 编排单次批量转存和单次统一刷新。页面只负责目录选择、来源持久化和分级反馈，复用现有目录选择器与 `CloudSourceRootRefreshCoordinator`。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、ChangeNotifier、Hive CE、flutter_test、Windows MSIX

## 文件结构

- 新建 `lib/services/cloud/quark/quark_transfer_target_policy.dart`：纯函数合并默认转存目录和媒体根目录。
- 修改 `lib/repositories/quark_import_history_repository.dart`：增加原子批量占用与批量保存。
- 修改 `lib/providers/quark_import_controller.dart`：增加批量转存结果和单次刷新编排。
- 修改 `lib/pages/cloud/quark/quark_share_import_page.dart`：增加目录选择、来源保存和完整/部分成功反馈。
- 修改 `lib/pages/settings/settings_module.dart`：向生产页面注入来源控制器和统一刷新入口。
- 修改夸克相关测试：覆盖路径策略、原子幂等、批量转存和页面交互。
- 修改版本与发布文件：发布 `2.1.44+20144` 测试版并保持全部一致性检查通过。

### Task 1: 合并转存目标和媒体根目录

**Files:**
- Create: `lib/services/cloud/quark/quark_transfer_target_policy.dart`
- Create: `test/quark_transfer_target_policy_test.dart`

- [ ] **Step 1: 写目录合并策略的失败测试**

在 `test/quark_transfer_target_policy_test.dart` 写三个测试：未覆盖目录会追加、上级目录已覆盖时不重复、同路径远程 ID 变化时替换旧引用。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/quark/quark_transfer_target_policy.dart';

void main() {
  const source = CloudSource(
    id: 'quark-a',
    type: CloudSourceType.quark,
    name: '夸克网盘',
    baseUrl: 'https://pan.quark.cn',
    rootPaths: <String>['/影视'],
    rootRefs: <CloudRemoteRef>[
      CloudRemoteRef(id: 'movies-id', path: '/影视'),
    ],
  );

  test('未覆盖的转存目录会成为默认目录和媒体根目录', () {
    const target = CloudRemoteRef(id: 'incoming-id', path: '/接收');
    final updated = QuarkTransferTargetPolicy.apply(source, target);

    expect(updated.defaultTransferDirectory, target);
    expect(updated.remoteRoots, contains(target));
    expect(updated.rootPaths, <String>['/影视', '/接收']);
  });

  test('已有上级媒体根目录时不重复追加转存目录', () {
    const target = CloudRemoteRef(id: 'season-id', path: '/影视/电视剧');
    final updated = QuarkTransferTargetPolicy.apply(source, target);

    expect(updated.defaultTransferDirectory, target);
    expect(updated.remoteRoots, source.remoteRoots);
  });

  test('同路径远程 ID 变化时替换旧根引用', () {
    const target = CloudRemoteRef(id: 'new-movies-id', path: '/影视');
    final updated = QuarkTransferTargetPolicy.apply(source, target);

    expect(updated.remoteRoots, <CloudRemoteRef>[target]);
  });
}
```

- [ ] **Step 2: 运行测试并确认因策略类不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_transfer_target_policy_test.dart`

Expected: FAIL，提示找不到 `quark_transfer_target_policy.dart` 或 `QuarkTransferTargetPolicy`。

- [ ] **Step 3: 实现最小目录合并策略**

在 `lib/services/cloud/quark/quark_transfer_target_policy.dart` 实现：

```dart
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';

abstract final class QuarkTransferTargetPolicy {
  static CloudSource apply(CloudSource source, CloudRemoteRef target) {
    final normalizedTarget = CloudSourcePathScope.normalizePath(target.path);
    final roots = List<CloudRemoteRef>.from(source.remoteRoots);
    final exactIndex = roots.indexWhere(
      (root) =>
          CloudSourcePathScope.normalizePath(root.path) == normalizedTarget,
    );
    if (exactIndex >= 0) {
      roots[exactIndex] = target;
    } else if (!CloudSourcePathScope.containsSourcePath(source, target.path)) {
      roots.add(target);
    }
    return source.copyWith(
      defaultTransferDirectory: target,
      rootRefs: List<CloudRemoteRef>.unmodifiable(roots),
      rootPaths: List<String>.unmodifiable(
        roots.map((root) => root.path),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行定向测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\quark_transfer_target_policy_test.dart test\cloud_source_path_scope_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交目录策略**

```powershell
git add lib/services/cloud/quark/quark_transfer_target_policy.dart test/quark_transfer_target_policy_test.dart
git commit -m "功能：联动夸克转存目录和扫描范围"
```

### Task 2: 原子占用和保存批量转存历史

**Files:**
- Modify: `lib/repositories/quark_import_history_repository.dart`
- Modify: `test/quark_import_history_repository_test.dart`

- [ ] **Step 1: 写整批成功与整批拒绝的失败测试**

在 `test/quark_import_history_repository_test.dart` 增加辅助函数和两个测试：

```dart
QuarkImportRecord record(String fileId) => QuarkImportRecord(
      sourceId: 'source-fixture',
      shareId: 'share-fixture',
      sharedFileId: fileId,
      targetDirectoryId: 'target-fixture',
      displayName: fileId,
      status: QuarkImportStatus.pending,
      createdAt: DateTime.utc(2026, 7, 24),
      updatedAt: DateTime.utc(2026, 7, 24),
    );

test('批量占用在同一次写入中保存全部记录', () async {
  final repository = QuarkImportHistoryRepository(
    storage: MemoryQuarkImportHistoryStorage(),
  );
  expect(await repository.tryBeginAll([record('a'), record('b')]), isTrue);
  expect(await repository.getAll(), hasLength(2));
});

test('批量包含重复项时不留下其他待处理记录', () async {
  final repository = QuarkImportHistoryRepository(
    storage: MemoryQuarkImportHistoryStorage(),
  );
  await repository.save(record('a').copyWith(
    status: QuarkImportStatus.succeeded,
  ));

  expect(await repository.tryBeginAll([record('a'), record('b')]), isFalse);
  final records = await repository.getAll();
  expect(records, hasLength(1));
  expect(records.single.sharedFileId, 'a');
});
```

- [ ] **Step 2: 运行测试并确认新方法缺失**

Run: `D:\flutter\bin\flutter.bat test test\quark_import_history_repository_test.dart`

Expected: FAIL，提示 `tryBeginAll` 未定义。

- [ ] **Step 3: 实现原子批量仓库方法**

在 `QuarkImportHistoryRepository` 中增加：

```dart
Future<bool> tryBeginAll(List<QuarkImportRecord> pending) =>
    _lock.synchronized(() async {
      if (pending.isEmpty) return false;
      final keys = pending.map((record) => record.idempotencyKey).toSet();
      if (keys.length != pending.length) return false;
      final records = _decode(await _storage.read());
      final blocked = records.any(
        (record) => keys.contains(record.idempotencyKey) && record.blocksDuplicate,
      );
      if (blocked) return false;
      records.removeWhere((record) => keys.contains(record.idempotencyKey));
      records.addAll(pending);
      await _storage.write(records.map((record) => record.toJson()).toList());
      return true;
    });

Future<void> saveAll(List<QuarkImportRecord> updates) =>
    _lock.synchronized(() async {
      final keys = updates.map((record) => record.idempotencyKey).toSet();
      final records = _decode(await _storage.read())
        ..removeWhere((record) => keys.contains(record.idempotencyKey))
        ..addAll(updates);
      await _storage.write(records.map((record) => record.toJson()).toList());
    });
```

让现有 `tryBegin` 委托 `tryBeginAll(<QuarkImportRecord>[record])`，让 `save` 委托 `saveAll(<QuarkImportRecord>[record])`，避免两套幂等逻辑分叉。

- [ ] **Step 4: 运行历史仓库测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\quark_import_history_repository_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交批量历史支持**

```powershell
git add lib/repositories/quark_import_history_repository.dart test/quark_import_history_repository_test.dart
git commit -m "功能：原子记录夸克批量转存"
```

### Task 3: 批量转存后只刷新一次媒体库

**Files:**
- Modify: `lib/providers/quark_import_controller.dart`
- Modify: `test/quark_import_controller_test.dart`

- [ ] **Step 1: 写批量转存、重复拦截和部分成功的失败测试**

把测试假服务增加 `saveCalls`、`savedEntries`，并新增以下行为断言：

```dart
test('多个条目共用一个转存任务且只刷新一次', () async {
  final transfer = _FakeTransferService();
  var refreshes = 0;
  final controller = QuarkImportController(
    historyRepository: QuarkImportHistoryRepository(
      storage: MemoryQuarkImportHistoryStorage(),
    ),
    transferService: transfer,
    refreshSource: (_) async => refreshes++,
  );

  final result = await controller.importEntries(
    sourceId: 'source-fixture',
    shareId: 'share-fixture',
    entries: const <QuarkShareEntry>[
      entry,
      QuarkShareEntry(
        id: 'shared-second',
        name: '示例目录二',
        isDirectory: true,
        size: 0,
        fileToken: 'file-token-second',
      ),
    ],
    targetDirectoryId: 'target-fixture',
  );

  expect(result.libraryRefreshed, isTrue);
  expect(transfer.saveCalls, 1);
  expect(transfer.savedEntries, hasLength(2));
  expect(refreshes, 1);
});

test('整批存在重复项时不发起转存', () async {
  final repository = QuarkImportHistoryRepository(
    storage: MemoryQuarkImportHistoryStorage(),
  );
  final transfer = _FakeTransferService();
  final controller = QuarkImportController(
    historyRepository: repository,
    transferService: transfer,
    refreshSource: (_) async {},
  );
  await controller.importEntries(
    sourceId: 'source-fixture',
    shareId: 'share-fixture',
    entries: const <QuarkShareEntry>[entry],
    targetDirectoryId: 'target-fixture',
  );

  await expectLater(
    controller.importEntries(
      sourceId: 'source-fixture',
      shareId: 'share-fixture',
      entries: const <QuarkShareEntry>[entry],
      targetDirectoryId: 'target-fixture',
    ),
    throwsA(isA<QuarkDuplicateImportException>()),
  );
  expect(transfer.saveCalls, 1);
});

test('转存成功但刷新失败时历史保持成功', () async {
  final repository = QuarkImportHistoryRepository(
    storage: MemoryQuarkImportHistoryStorage(),
  );
  final controller = QuarkImportController(
    historyRepository: repository,
    transferService: _FakeTransferService(),
    refreshSource: (_) async => throw StateError('模拟刷新失败'),
  );

  final result = await controller.importEntries(
    sourceId: 'source-fixture',
    shareId: 'share-fixture',
    entries: const <QuarkShareEntry>[entry],
    targetDirectoryId: 'target-fixture',
  );

  expect(result.libraryRefreshed, isFalse);
  expect(result.refreshError, isA<StateError>());
  expect((await repository.getAll()).single.status,
      QuarkImportStatus.succeeded);
});
```

- [ ] **Step 2: 运行控制器测试并确认新 API 缺失**

Run: `D:\flutter\bin\flutter.bat test test\quark_import_controller_test.dart`

Expected: FAIL，提示 `refreshSource` 或 `importEntries` 未定义。

- [ ] **Step 3: 实现批量控制器和可区分结果**

在 `quark_import_controller.dart` 中定义：

```dart
typedef QuarkSourceRefresher = Future<void> Function(String sourceId);

class QuarkImportBatchResult {
  const QuarkImportBatchResult({
    required this.task,
    this.refreshError,
  });

  final QuarkTransferTask task;
  final Object? refreshError;
  bool get libraryRefreshed => refreshError == null;
}
```

把控制器依赖改为 `required QuarkSourceRefresher refreshSource`。新增 `importEntries`：先构造全部 pending 记录并调用 `tryBeginAll`，再用全部条目调用一次 `saveShare`，用 `saveAll` 同步任务号和终态。服务端成功后捕获刷新异常并放入 `QuarkImportBatchResult.refreshError`。服务端失败、超时或取消时批量写入对应状态并重新抛出 `CloudDriveException`。

保留 `importEntry` 兼容入口，但内部只调用一次 `importEntries` 并返回 `result.task`：

```dart
Future<QuarkTransferTask> importEntry({
  required String sourceId,
  required String shareId,
  required QuarkShareEntry entry,
  required String targetDirectoryId,
}) async {
  final result = await importEntries(
    sourceId: sourceId,
    shareId: shareId,
    entries: <QuarkShareEntry>[entry],
    targetDirectoryId: targetDirectoryId,
  );
  return result.task;
}
```

- [ ] **Step 4: 更新假服务并运行控制器与服务测试**

假服务的 `saveShare` 保存 `entries` 并递增 `saveCalls`。运行：

`D:\flutter\bin\flutter.bat test test\quark_import_controller_test.dart test\quark_share_transfer_service_test.dart test\quark_import_history_repository_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交批量编排**

```powershell
git add lib/providers/quark_import_controller.dart test/quark_import_controller_test.dart
git commit -m "功能：夸克批量转存后统一刷新"
```

### Task 4: 在分享导入页选择并保存转存目录

**Files:**
- Modify: `lib/pages/cloud/quark/quark_share_import_page.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `test/quark_share_import_page_test.dart`

- [ ] **Step 1: 写未设置目录时仍可选择的失败测试**

扩展 `QuarkShareImportPage` 的测试依赖，传入内存来源仓库、`CloudLibraryController` 和返回 `/接收` 的假网盘客户端。新增测试：

```dart
testWidgets('未设置转存目录时可在导入页选择并自动加入媒体根目录',
    (tester) async {
  final credentials = MemoryCloudCredentialStore();
  final repository = CloudSourceRepository(
    storage: MemoryCloudSourceStorage(),
    credentialStore: credentials,
  );
  const source = CloudSource(
    id: 'quark-target',
    type: CloudSourceType.quark,
    name: '夸克媒体库',
    baseUrl: 'https://pan.quark.cn',
    rootPaths: <String>['/影视'],
    rootRefs: <CloudRemoteRef>[
      CloudRemoteRef(id: 'movies-id', path: '/影视'),
    ],
  );
  await repository.save(source);
  final cloudController = CloudLibraryController(
    repository: repository,
    credentialStore: credentials,
    clientFactory: (_, __, ___) => _DirectoryClient(),
  );
  final transfer = _PageTransferService();

  await tester.pumpWidget(MaterialApp(
    home: QuarkShareImportPage(
      source: source,
      cloudLibraryController: cloudController,
      transferService: transfer,
      importController: _importer(transfer),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('转存到：未设置'), findsOneWidget);
  await tester.tap(find.widgetWithText(OutlinedButton, '选择目录'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('select-target-id')));
  await tester.tap(find.text('确定'));
  await tester.pumpAndSettle();

  expect(find.text('转存到：/接收'), findsOneWidget);
  final saved = await repository.getById(source.id);
  expect(saved?.defaultTransferDirectory,
      const CloudRemoteRef(id: 'target-id', path: '/接收'));
  expect(saved?.rootPaths, contains('/接收'));
});
```

在同一测试文件中加入真实接口的最小假实现：

```dart
QuarkImportController _importer(
  QuarkShareTransfer transfer, {
  QuarkSourceRefresher? refreshSource,
}) =>
    QuarkImportController(
      historyRepository: QuarkImportHistoryRepository(
        storage: MemoryQuarkImportHistoryStorage(),
      ),
      transferService: transfer,
      refreshSource: refreshSource ?? (_) async {},
    );

class _DirectoryClient implements CloudDriveClient {
  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async =>
      const <CloudFileEntry>[
        CloudFileEntry(
          id: 'target-id',
          remotePath: '/接收',
          name: '接收',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ];

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
```

- [ ] **Step 2: 写批量转存只触发一次刷新及部分成功提示测试**

让 `_PageTransferService.inspectShare` 返回两个条目。勾选两项并点击转存后，断言 `saveCalls == 1` 且页面显示“转存完成，已扫描到媒体库”。再用 `refreshSource` 抛错的 importer 重跑，断言显示“文件已转存，但媒体库刷新失败，请重试扫描”。

- [ ] **Step 3: 运行页面测试并确认缺少目录入口和新依赖**

Run: `D:\flutter\bin\flutter.bat test test\quark_share_import_page_test.dart`

Expected: FAIL，找不到“选择目录”按钮或 `cloudLibraryController` 参数。

- [ ] **Step 4: 实现页面目录选择与来源保存**

给 `QuarkShareImportPage` 增加可选 `CloudLibraryController cloudLibraryController` 依赖；生产环境为空时从 Modular 获取。状态中保存最新 `_source`，初始化时调用控制器 `load()` 并按 ID 读取最新来源。

新增 `_chooseTransferDirectory`：打开 `QuarkDirectoryPickerPage(singleSelection: true)`，将结果交给 `QuarkTransferTargetPolicy.apply`，再调用 `CloudLibraryController.save(updated)`。保存成功后更新 `_source`，失败则显示“转存目录保存失败，请重试”且不改变可提交状态。

把顶部文本改为带按钮的 `Row`，按钮文字按是否已有目标显示“选择目录”或“更改目录”。转存期间禁用按钮。

- [ ] **Step 5: 接入批量转存与统一刷新协调器**

页面创建 `QuarkImportController` 时注入：

```dart
refreshSource: Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
```

将 `_importSelected` 中的逐项循环替换为一次 `importEntries`。根据 `result.libraryRefreshed` 显示完整成功或部分成功提示。

在 `settings_module.dart` 的夸克导入路由显式传入共享 `CloudLibraryController`，避免页面创建第二个来源控制器。

- [ ] **Step 6: 运行页面、控制器和来源测试**

Run: `D:\flutter\bin\flutter.bat test test\quark_share_import_page_test.dart test\quark_import_controller_test.dart test\quark_source_editor_test.dart test\cloud_source_root_refresh_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交导入页闭环**

```powershell
git add lib/pages/cloud/quark/quark_share_import_page.dart lib/pages/settings/settings_module.dart test/quark_share_import_page_test.dart
git commit -m "功能：夸克转存后扫描媒体资源"
```

### Task 5: 更新 2.1.44 测试版信息

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 先把一致性测试期望改为测试版并运行失败**

将 `test/version_consistency_test.dart` 的期望改为：

```dart
const expectedVersion = '2.1.44';
const expectedBuildNumber = '20144';
```

把“正式版”断言改为“测试版”，并断言当前 `VersionHistory` 包含 `isPrerelease: true`。在 `version_history_current_test.dart` 增加：

```dart
test('二点一四十四说明夸克转存目录与扫描联动', () {
  final entry = versionHistoryForCurrent('2.1.44').single;
  final changes = entry.changes.join('\n');
  expect(entry.isPrerelease, isTrue);
  expect(changes, contains('转存目录'));
  expect(changes, contains('媒体根目录'));
  expect(changes, contains('扫描'));
  expect(changes, contains('不会修改网盘文件'));
});
```

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，因为生产版本仍为 `1.0.1`。

- [ ] **Step 2: 更新全部版本来源和用户文案**

使用以下版本：

- `pubspec.yaml`: `version: 2.1.44+20144`
- `pubspec.yaml`: `msix_version: 2.1.44.0`
- `lib/core/app_version.dart`: `current = '2.1.44'`
- `README.md`: 当前版本 `2.1.44`
- `UPDATE_DIALOG_COPY.md`: 应用版本 `2.1.44`、安装包版本 `2.1.44.0`、标题“看影音 2.1.44 测试版”

在 `RELEASE_NOTES.md` 和 `version_history.dart` 顶部加入普通用户文案：导入页可选择转存目录、目标自动加入扫描范围、批量转存后只刷新一次、TMDB 断网不影响扫描播放、不会修改网盘原文件。`VersionHistory` 设置 `isPrerelease: true`。

- [ ] **Step 3: 运行版本与发布契约测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart test\signed_release_packaging_test.dart`

Expected: PASS。

- [ ] **Step 4: 提交版本与发布说明**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md README.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "版本：发布二点一四十四测试版"
```

### Task 6: 完整验证、代码审查与 MSIX 交付

**Files:**
- Verify only; packaging outputs stay under `build/` and the current user's desktop.

- [ ] **Step 1: 检查改动范围和编码问题**

```powershell
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
git status --short
git diff --check HEAD~4
git diff --stat HEAD~4
```

Expected: 只有本计划列出的功能、测试和版本文件，无空白错误。

- [ ] **Step 2: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: PASS，0 个失败。

- [ ] **Step 3: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`。

- [ ] **Step 4: 请求代码审查并处理重要问题**

用 `superpowers:requesting-code-review` 派发审查，范围从 `ec05c3c` 到当前 HEAD。审查要求覆盖：批量历史原子性、转存成功与扫描失败的状态分离、页面销毁安全、目录 ID 更新和不删除原文件。修复 Critical/Important 问题后重新运行定向测试、完整测试和静态分析。

- [ ] **Step 5: 构建全新 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit 0，并且以下文件时间晚于本轮代码提交：

- `build\windows\x64\runner\Release\kanyingyin.exe`
- `build\windows\x64\runner\Release\data\app.so`

- [ ] **Step 6: 生成、签名并复制 MSIX 到桌面**

优先运行仓库现有签名发布脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 桌面生成 `看影音-2.1.44.msix`，签名状态为 `Valid`。如果签名材料缺失，则记录明确阻塞；不得交付未签名包冒充最终包。

- [ ] **Step 7: 校验清单、哈希和桌面产物**

检查 MSIX 内 `AppxManifest.xml`：

- `Identity Name="com.kanyingyin.player"`
- `Version="2.1.44.0"`
- `ProcessorArchitecture="x64"`

记录桌面文件绝对路径、大小、修改时间和 SHA-256。

- [ ] **Step 8: 再次核对本机安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name,PackageFullName,Version,InstallLocation
```

Expected: 未执行安装时仍为已记录的 `2.1.43.0`。本轮不自动安装，除非用户明确要求。

- [ ] **Step 9: 最终状态检查**

```powershell
git status --short
git log -6 --oneline
```

Expected: 工作树干净，功能、版本和文档提交均存在。

- [ ] **Step 10: 交付报告中记录 TMDB 根因边界**

明确报告附件机器的请求在 HTTP 鉴权前连接超时，相同 API Key 已排除密钥差异；建议在该机器核对 DNS、网络出口、代理和防火墙。不得宣称通过本次转存代码修复了外部网络问题。
