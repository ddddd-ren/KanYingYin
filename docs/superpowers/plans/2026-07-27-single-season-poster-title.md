# Single-Season Poster Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 单一第一季作品的网盘海报标题只显示作品名，多季作品和单一非第一季作品继续显示季号。

**Architecture:** 在 `CloudResourceCollectionGrouper` 将作品季度转换为海报分组时计算展示标题。只改变 `CloudResourceMediaGroup.displayName`，保留作品键、季度编号、TMDB 元数据、搜索、选集和播放路径。

**Tech Stack:** Flutter 3.41.9、Dart、flutter_test、Flutter Modular、MobX、Windows MSIX

---

### Task 1: 用测试锁定单季和多季标题规则

**Files:**
- Modify: `test/cloud_resource_collection_test.dart`

- [ ] **Step 1: 让作品测试工厂支持指定季度**

将 `_workIdentity` 改为接收季度列表，并保持现有调用默认生成三季：

```dart
CloudWorkIdentity _workIdentity({
  String sourceId = 'quark',
  List<int> seasonNumbers = const <int>[1, 2, 3],
}) {
  // 保留现有 root、标题和作品键初始化。
  return CloudWorkIdentity(
    sourceId: sourceId,
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: '规则标题',
    titleCandidates: const <String>['规则标题', 'Original Title'],
    seasons: <CloudSeasonIdentity>[
      for (final season in seasonNumbers)
        CloudSeasonIdentity(
          workKey: workKey,
          seasonNumber: season,
          displayName: '规则标题 第 $season 季',
          remoteDirectories: const <CloudFileEntry>[],
          episodes: const <CloudEpisodeIdentity>[],
        ),
    ],
  );
}
```

- [ ] **Step 2: 写入单一第一季失败断言**

将“已匹配作品修改刮削名称后海报卡优先显示手动名称”和“回魂计按九个唯一集号展示并保留二十七个真实版本”的作品改为：

```dart
final work = _workIdentity(seasonNumbers: const <int>[1]);
```

并将对应标题断言改为：

```dart
expect(collection.groups.single.displayName, '回魂计');
```

- [ ] **Step 3: 添加单一第二季保留季号测试**

构造 `seasonNumbers: const <int>[2]` 的作品及一个第二季索引项，断言：

```dart
expect(collection.groups.single.displayName, '规则标题 第 2 季');
```

- [ ] **Step 4: 运行测试并确认红灯原因**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact test/cloud_resource_collection_test.dart
```

Expected: 单一第一季仍实际得到“回魂计 第 1 季”，新断言失败；现有三季测试仍通过。

### Task 2: 实现最小标题规则

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_collection.dart:239-270`
- Test: `test/cloud_resource_collection_test.dart`

- [ ] **Step 1: 在季度循环前判断是否为单一第一季**

在 `work.seasons.isEmpty` 分支之后、季度循环之前加入：

```dart
final omitOnlyFirstSeasonSuffix =
    work.seasons.length == 1 && work.seasons.single.seasonNumber == 1;
```

- [ ] **Step 2: 仅调整海报分组展示名**

将季度分组的 `displayName` 改为：

```dart
displayName: omitOnlyFirstSeasonSuffix
    ? title
    : '$title 第 ${season.seasonNumber} 季',
```

不修改 `stableKey`、`seasonNumber`、`seriesName`、`seasonMetadata` 或视频列表。

- [ ] **Step 3: 运行目标测试确认转绿**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact test/cloud_resource_collection_test.dart test/cloud_resources_page_test.dart
```

Expected: 全部通过；三季作品仍显示三个季号，单一第二季仍显示“第 2 季”。

- [ ] **Step 4: 提交行为修改**

```powershell
git add lib/pages/cloud/resources/cloud_resource_collection.dart test/cloud_resource_collection_test.dart
git commit -m "精简单季作品海报标题"
```

### Task 3: 更新 2.1.62 交付信息

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 更新版本号**

使用以下一致版本：

```text
version: 2.1.62+20162
msix_version: 2.1.62.0
AppVersion.current = '2.1.62'
```

- [ ] **Step 2: 更新用户文案**

在三个用户文案入口说明：单一第一季隐藏季度后缀，多季或单一非第一季仍保留季号；改动仅影响展示，不修改网盘文件或播放路径。

- [ ] **Step 3: 更新版本一致性测试**

将期望版本改为 `2.1.62 / 20162`，并断言当前版本文案包含“单一第一季”“多季作品”“不会修改或删除”。

- [ ] **Step 4: 运行版本测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交版本文件**

```powershell
git add pubspec.yaml lib/core/app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布：准备二点一六十二测试版"
```

### Task 4: 完整验证与 Windows 交付

**Files:**
- Verify: `C:\Users\asus\Desktop\看影音-2.1.62.msix`

- [ ] **Step 1: 运行完整质量门禁**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 测试零失败、静态分析无问题、Release 构建成功。

- [ ] **Step 2: 生成签名 MSIX**

确认看影音进程已退出后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 桌面生成 `看影音-2.1.62.msix` 和异机安装包。

- [ ] **Step 3: 验证交付包**

核对 MSIX 清单为 `com.kanyingyin.player / 2.1.62.0 / x64`、签名状态为 `Valid`，构建目录包与桌面包 SHA-256 一致，并再次查询已安装版本。

- [ ] **Step 4: 合入主分支并在合并结果复测**

快进合入 `main` 后重新运行完整 `flutter test`，确认通过再清理隔离工作树。
