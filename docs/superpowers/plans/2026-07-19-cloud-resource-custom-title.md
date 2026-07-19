# 网盘资源自定义剧名实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为网盘文件夹和媒体根目录独立视频增加仅作用于看影音内部的自定义剧名，并将该名称用于 TMDB 查询，支持一键恢复 TMDB 标题。

**Architecture:** 在现有 `CloudResourceTmdbRecord` 中持久化 `customTitle`，继续复用资源稳定键、仓库和来源删除事务。控制器与协调器负责保存/清除名称，TMDB 目标携带自定义查询名，服务生成 matched、unmatched、failed 记录时保留该字段；页面只修改应用内记录，绝不调用远程重命名接口。

**Tech Stack:** Flutter 3.41.9、Flutter Modular、Hive、现有 `CloudResourceTmdbRepository`/`CloudResourceTmdbCoordinator`/`CloudResourceTmdbService`、flutter_test、Windows Release、MSIX 3.18.0。

**执行约束:** 用户明确禁止子智能体；使用 `superpowers:executing-plans` 在当前会话内联执行，严格遵循 TDD。

---

## 文件结构

- Modify `lib/modules/cloud/cloud_resource_tmdb_record.dart`：增加自定义剧名、有效标题和不可变更新方法。
- Modify `lib/services/cloud/cloud_resource_tmdb_service.dart`：目标携带自定义名称，所有状态更新保留该名称。
- Modify `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`：保存、清除自定义剧名并在调度中传递。
- Modify `lib/pages/cloud/resources/cloud_resources_controller.dart`：向页面暴露修改/恢复 API。
- Modify `lib/pages/cloud/resources/cloud_resources_grid.dart`：卡片显示有效标题，菜单增加“修改剧名”。
- Modify `lib/pages/cloud/resources/cloud_resources_page.dart`：实现输入、校验、保存与恢复对话框。
- Modify `lib/utils/version_history.dart`、`lib/core/app_version.dart`、`pubspec.yaml`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`：交付 2.1.7。
- Modify tests：`cloud_resource_tmdb_record_test.dart`、`cloud_resource_tmdb_service_test.dart`、`cloud_resource_tmdb_coordinator_test.dart`、`cloud_resources_page_test.dart`、`cloud_source_cleanup_test.dart` 和版本一致性测试。

### Task 1: 自定义剧名模型与持久化

**Files:**
- Modify: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Test: `test/cloud_resource_tmdb_record_test.dart`
- Test: `test/cloud_resource_tmdb_repository_test.dart`

- [ ] **Step 1: 写模型红灯测试**

在 `test/cloud_resource_tmdb_record_test.dart` 增加：

```dart
test('自定义剧名优先显示且清除后恢复 TMDB 标题', () {
  final customized = matched.withCustomTitle('  我的剧名  ');
  expect(customized.customTitle, '我的剧名');
  expect(customized.effectiveTitle, '我的剧名');
  expect(CloudResourceTmdbRecord.fromJson(customized.toJson()), customized);

  final restored = customized.clearCustomTitle();
  expect(restored.customTitle, isNull);
  expect(restored.effectiveTitle, matched.title);
});

test('未匹配资源也能保存自定义剧名', () {
  final record = CloudResourceTmdbRecord.unchecked(
    sourceId: 'source-a',
    remoteId: 'folder-a',
    remotePath: '/影视/A',
    displayName: 'A',
    resourceKind: CloudResourceKind.directory,
    checkedAt: DateTime.utc(2026, 7, 19),
  ).withCustomTitle('自定义 A');
  expect(record.status, CloudResourceTmdbStatus.unchecked);
  expect(record.effectiveTitle, '自定义 A');
});
```

- [ ] **Step 2: 运行测试确认红灯**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_record_test.dart
```

Expected: FAIL，提示 `customTitle`、`effectiveTitle`、`withCustomTitle`、`clearCustomTitle` 或 `unchecked` 不存在。

- [ ] **Step 3: 实现最小模型能力**

在 `CloudResourceTmdbRecord` 中增加：

```dart
final String? customTitle;

String get effectiveTitle {
  final custom = customTitle?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final matchedTitle = title?.trim();
  if (matchedTitle != null && matchedTitle.isNotEmpty) return matchedTitle;
  return displayName;
}

CloudResourceTmdbRecord withCustomTitle(String value) => _copyWithCustomTitle(
      value.trim().isEmpty ? null : value.trim(),
    );

CloudResourceTmdbRecord clearCustomTitle() => _copyWithCustomTitle(null);
```

为公共构造器、`matched`、`unmatched`、`failed`、新增 `unchecked`、`fromJson`、`toJson`、`==` 和 `hashCode` 接入 `customTitle`。`withCustomTitle` 收到空白时不得创建空字符串字段。

- [ ] **Step 4: 写仓库往返红灯测试**

在 `test/cloud_resource_tmdb_repository_test.dart` 增加：

```dart
test('仓库更新自定义剧名时保留稳定键和 TMDB 信息', () async {
  final repository = CloudResourceTmdbRepository(
    storage: MemoryCloudResourceTmdbStorage(),
  );
  final original = _matchedRecord();
  await repository.upsert(original);
  await repository.upsert(original.withCustomTitle('新剧名'));

  final stored = await repository.get(original.stableKey);
  expect(stored?.customTitle, '新剧名');
  expect(stored?.tmdbId, original.tmdbId);
  expect(stored?.stableKey, original.stableKey);
});

CloudResourceTmdbRecord _matchedRecord() =>
    CloudResourceTmdbRecord.matched(
      sourceId: 'source-a',
      remoteId: 'folder-a',
      remotePath: '/影视/A',
      displayName: 'A',
      resourceKind: CloudResourceKind.directory,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: 'TMDB 标题',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 19),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 7, 19),
    );
```

- [ ] **Step 5: 格式化并运行绿灯**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\modules\cloud\cloud_resource_tmdb_record.dart test\cloud_resource_tmdb_record_test.dart test\cloud_resource_tmdb_repository_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_record_test.dart test\cloud_resource_tmdb_repository_test.dart
```

Expected: PASS。

- [ ] **Step 6: 提交模型阶段**

```powershell
git add lib/modules/cloud/cloud_resource_tmdb_record.dart test/cloud_resource_tmdb_record_test.dart test/cloud_resource_tmdb_repository_test.dart
git commit -m '功能：持久化网盘自定义剧名'
```

### Task 2: TMDB 查询与状态保留

**Files:**
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Test: `test/cloud_resource_tmdb_service_test.dart`
- Test: `test/cloud_resource_tmdb_coordinator_test.dart`

- [ ] **Step 1: 写服务查询红灯测试**

```dart
test('自定义剧名成为 TMDB 查询词且不改变远程路径', () async {
  final target = CloudResourceTmdbTarget(
    sourceId: 'source-a',
    remote: const CloudRemoteRef(id: 'folder-a', path: '/影视/原目录'),
    displayName: '原目录',
    resourceKind: CloudResourceKind.directory,
    customTitle: '自定义剧名',
  );
  await service.searchCandidates(target);
  expect(client.queries.first, '自定义剧名');
  expect(target.remote.path, '/影视/原目录');
});

test('匹配和未匹配记录都保留自定义剧名', () async {
  final outcome = await service.match(customTarget);
  final stored = await repository.get(customTarget.stableKey);
  expect(stored?.customTitle, '自定义剧名');
  expect(outcome.selected?.customTitle, '自定义剧名');
});
```

- [ ] **Step 2: 运行服务测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_service_test.dart
```

Expected: FAIL，目标没有 `customTitle` 或查询仍使用 `displayName`。

- [ ] **Step 3: 实现目标与服务保留逻辑**

为 `CloudResourceTmdbTarget` 增加 `String? customTitle` 和：

```dart
String get queryDisplayName {
  final custom = customTitle?.trim();
  return custom == null || custom.isEmpty ? displayName : custom;
}
```

`CloudResourceTmdbService._search()` 使用 `target.queryDisplayName`。创建 `matched`、`unmatched` 记录时传入 `customTitle: target.customTitle`；海报缓存稳定 ID 和远程同步条件继续使用稳定键与远程路径，不使用自定义标题。

- [ ] **Step 4: 写协调器保存/恢复红灯测试**

```dart
test('没有 TMDB Key 也能保存和恢复自定义剧名', () async {
  await coordinator.saveCustomTitle(target, '  新剧名  ');
  expect(coordinator.records[target.stableKey]?.effectiveTitle, '新剧名');
  expect(client.searchCalls, 0);

  await coordinator.clearCustomTitle(target);
  expect(coordinator.records[target.stableKey]?.customTitle, isNull);
  expect(client.searchCalls, 0);
});

test('失败状态更新不丢失自定义剧名', () async {
  await coordinator.saveCustomTitle(target, '新剧名');
  await coordinator.loadAndSchedule(context);
  final stored = await repository.get(target.stableKey);
  expect(stored?.status, CloudResourceTmdbStatus.failed);
  expect(stored?.customTitle, '新剧名');
});
```

- [ ] **Step 5: 实现协调器与控制器 API**

协调器增加：

```dart
Future<CloudResourceTmdbRecord> saveCustomTitle(
  CloudResourceTmdbTarget target,
  String title,
);

Future<CloudResourceTmdbRecord> clearCustomTitle(
  CloudResourceTmdbTarget target,
);
```

保存时读取现有记录；不存在则以 `CloudResourceTmdbRecord.unchecked(...)` 创建。写入成功后更新 `_records` 并通知监听器。调度目标、手动目标和失败记录都携带缓存中的 `customTitle`。

控制器增加：

```dart
Future<CloudResourceTmdbRecord> saveCustomTitle(
  CloudFileEntry entry,
  String title,
) => coordinator.saveCustomTitle(tmdbTargetFor(entry), title);

Future<CloudResourceTmdbRecord> clearCustomTitle(
  CloudFileEntry entry,
) => coordinator.clearCustomTitle(tmdbTargetFor(entry));
```

`tmdbTargetFor()` 从当前记录读取 `customTitle`。

- [ ] **Step 6: 运行服务与协调器绿灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_service_test.dart test\cloud_resource_tmdb_coordinator_test.dart test\cloud_resources_controller_test.dart
```

Expected: PASS。

- [ ] **Step 7: 提交业务阶段**

```powershell
git add lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resource_tmdb_service_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m '功能：使用自定义剧名查询 TMDB'
```

### Task 3: 修改剧名与恢复界面

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写界面红灯测试**

```dart
testWidgets('资源菜单修改剧名后立即显示且保留原文件名', (tester) async {
  await tester.pumpWidget(page);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('资源操作'));
  await tester.tap(find.text('修改剧名'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('cloud-title-input')), '新剧名');
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();
  expect(find.text('新剧名'), findsOneWidget);
  expect(find.text('原文件夹'), findsOneWidget);
});

testWidgets('恢复 TMDB 标题只清除自定义剧名', (tester) async {
  await tester.pumpWidget(pageWithCustomTitle);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('资源操作'));
  await tester.tap(find.text('修改剧名'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('恢复 TMDB 标题'));
  await tester.pumpAndSettle();
  expect(find.text('TMDB 中文标题'), findsOneWidget);
  expect(find.text('原文件夹'), findsOneWidget);
});

testWidgets('空白剧名不会保存并显示提示', (tester) async {
  await tester.pumpWidget(page);
  await openTitleDialog(tester);
  await tester.enterText(find.byKey(const ValueKey('cloud-title-input')), '   ');
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pump();
  expect(find.text('剧名不能为空'), findsOneWidget);
});
```

- [ ] **Step 2: 运行页面测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart
```

Expected: FAIL，菜单没有“修改剧名”，页面没有输入对话框。

- [ ] **Step 3: 扩展网格回调和标题显示**

`CloudResourcesGrid` 增加 `onEditTitle` 回调，菜单顺序调整为：

```dart
const PopupMenuItem(
  value: _ResourceAction.editTitle,
  child: Text('修改剧名'),
),
const PopupMenuItem(
  value: _ResourceAction.scrape,
  child: Text('TMDB 刮削'),
),
const PopupMenuItem(
  value: _ResourceAction.rematch,
  child: Text('重新匹配'),
),
```

卡片主标题使用 `record?.effectiveTitle ?? entry.name`。有 TMDB 标题或自定义标题时继续显示 `entry.name` 作为辅助信息。

- [ ] **Step 4: 实现页面对话框**

页面增加 `_editTitle(CloudFileEntry entry)`：

```dart
final input = TextEditingController(
  text: _controller.tmdbRecordFor(entry)?.effectiveTitle ?? entry.name,
);
```

对话框输入框使用 `ValueKey('cloud-title-input')`。保存时 `trim()`，空白则在对话框中显示“剧名不能为空”；非空调用 `_controller.saveCustomTitle(entry, value)`。当前记录有 `customTitle` 时显示“恢复 TMDB 标题”，点击后调用 `_controller.clearCustomTitle(entry)` 并关闭对话框。所有控制器调用失败时关闭或保留对话框均不得改变已显示记录，并通过 SnackBar 显示“修改剧名失败”。

- [ ] **Step 5: 运行页面绿灯与静态分析**

```powershell
D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resources_grid.dart lib\pages\cloud\resources\cloud_resources_page.dart test\cloud_resources_page_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: PASS，静态分析无问题。

- [ ] **Step 6: 提交界面阶段**

```powershell
git add lib/pages/cloud/resources/cloud_resources_grid.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m '界面：支持修改网盘显示剧名'
```

### Task 4: 删除回滚与安全回归

**Files:**
- Modify: `test/cloud_source_cleanup_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 写含自定义剧名的删除与回滚测试**

将现有 `_resourceRecord()` 改为创建 `withCustomTitle('自定义剧名')` 的记录，并明确断言：

```dart
expect(await tmdbRepository.getBySource('source-a'), isEmpty);
expect((await tmdbRepository.getBySource('source-b')).single.customTitle,
    '自定义剧名');
```

来源删除失败后断言：

```dart
final restored = (await tmdbRepository.getBySource('source-a')).single;
expect(restored.customTitle, '自定义剧名');
expect(restored.remotePath, '/A');
```

- [ ] **Step 2: 写远程路径不变回归测试**

在控制器测试中保存自定义剧名后断言目录引用未变化，且客户端仍只执行原有目录读取：

```dart
await controller.saveCustomTitle(folder, '新剧名');
expect(controller.tmdbTargetFor(folder).remote.path, folder.remotePath);
expect(client.listed, contains(const CloudRemoteRef(id: 'root', path: '/影视')));
```

`CloudDriveClient` 没有重命名接口，因此不新增测试专用远程方法；通过目录引用断言和源码检查确认没有新增 rename/move/delete 调用。

- [ ] **Step 3: 运行安全回归**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_source_cleanup_test.dart test\cloud_resources_controller_test.dart test\cloud_playback_resolver_test.dart
rg "rename|move|delete" lib/pages/cloud/resources lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_coordinator.dart
```

Expected: 测试 PASS；搜索结果不包含对远程客户端执行重命名、移动或删除的代码。

- [ ] **Step 4: 提交安全阶段**

```powershell
git add test/cloud_source_cleanup_test.dart test/cloud_resources_controller_test.dart
git commit -m '测试：验证自定义剧名安全清理'
```

### Task 5: 2.1.7 全量验证与签名 MSIX

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 版本更新前完整门禁**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 格式无改动、全量测试通过、静态分析无问题。

- [ ] **Step 2: 先更新版本测试并确认红灯**

将三个版本测试的当前版本改为 `2.1.7`、构建号改为 `20107`，更新弹窗测试断言“修改剧名”和“不会重命名网盘文件”。运行：

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: FAIL，生产版本仍为 2.1.6。

- [ ] **Step 3: 更新版本与用户文案**

`pubspec.yaml`：

```yaml
version: 2.1.7+20107
msix_config:
  sign_msix: false
  msix_version: 2.1.7.0
```

`version_history.dart`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 和 `README.md` 面向普通用户说明：网盘资源支持修改显示剧名；自定义名称优先并用于 TMDB 搜索；可以恢复 TMDB 标题；不会修改网盘原始文件或路径；断网不影响显示和播放。

- [ ] **Step 4: 版本后完整门禁与 Release**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
$buildStart = Get-Date
D:\flutter\bin\flutter.bat build windows --release --no-pub
Get-Item build\windows\x64\runner\Release\kanyingyin.exe,build\windows\x64\runner\Release\data\app.so
```

Expected: 全部退出码为 0；`kanyingyin.exe` 和 `data/app.so` 时间晚于 `$buildStart`。

- [ ] **Step 5: 生成签名 MSIX**

用 `apply_patch` 临时将 `sign_msix: false` 改为 `true`。从 `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml` 读取 DPAPI 加密密码，仅在内存中解密，然后运行：

```powershell
D:\flutter\bin\dart.bat run msix:create --build-windows false --certificate-path "$env:USERPROFILE\.kanyingyin\signing\certificate.pfx" --certificate-password $plainPassword
```

命令结束后立即用 `apply_patch` 恢复 `sign_msix: false`。

- [ ] **Step 6: 验证并复制桌面安装包**

读取 `build\windows\x64\runner\Release\kanyingyin.msix` 内的 `AppxManifest.xml`，验证：

```text
Identity Name = com.kanyingyin.player
Identity Version = 2.1.7.0
ProcessorArchitecture = x64
Publisher = CN=KanYingYin
AppxSignature.p7x = 存在
Authenticode = Valid
```

复制为 `C:\Users\asus\Desktop\看影音-2.1.7.msix`，再次验证签名为 `Valid`，并确认源包与桌面包 SHA-256 一致。

- [ ] **Step 7: 审查并提交发布**

```powershell
git status --short
git diff --check
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m '发布：交付网盘自定义剧名 2.1.7'
```

`.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 始终保持未暂存、未提交；不 push。
