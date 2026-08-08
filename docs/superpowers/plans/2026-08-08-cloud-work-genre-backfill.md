# 云端作品 TMDB 题材补齐实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复已正确匹配 TMDB 但作品级题材为空的网盘动画电影无法同时进入“动漫”和“电影”的问题。

**Architecture:** 扩展现有 `LibraryGenreBackfillService`，从 `CloudWorkTmdbRepository` 收集题材缺失的已匹配作品，并与本地、云文件目标按 `(TmdbMediaType, id)` 去重。详情请求成功后仅把题材写回原有元数据，不重新搜索、不改变匹配身份；`LocalController` 通过依赖注入使用共享作品仓库。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、Flutter Modular、Hive 仓储、`flutter_test`、Inno Setup

---

## 文件结构

- 修改 `test/library_genre_backfill_service_test.dart`：增加作品级题材补齐、字段保留和跨索引请求去重回归测试。
- 修改 `lib/modules/cloud/cloud_work_tmdb_record.dart`：提供保留记录身份与状态的元数据替换方法，并让相等性包含题材。
- 修改 `lib/features/library/application/library_genre_backfill_service.dart`：读取、合并并写回云作品题材。
- 修改 `lib/pages/local/local_controller.dart`：把共享 `CloudWorkTmdbRepository` 传入补齐服务。
- 修改 `lib/app/bindings/library_bindings.dart`：注入应用级作品仓库单例。
- 修改 `pubspec.yaml`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：发布 2.1.153。

### 任务 1：记录交付前安装状态

- [x] **步骤 1：查询已安装 EXE 与旧 MSIX**

运行：

```powershell
$exe = 'D:\看影音\kanyingyin.exe'
if (Test-Path -LiteralPath $exe) { (Get-Item -LiteralPath $exe).VersionInfo | Select-Object ProductVersion, FileVersion }
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName -Like '*看影音*' | Select-Object DisplayName, DisplayVersion, InstallLocation
Get-AppxPackage | Where-Object Name -Like '*kanyingyin*' | Select-Object Name, Version, InstallLocation
```

预期：记录当前 EXE 产品版本、卸载注册表版本以及旧 MSIX 是否存在，不能根据 `pubspec.yaml` 推断。

### 任务 2：用失败测试复现作品题材遗漏

**文件：**

- 修改：`test/library_genre_backfill_service_test.dart`

- [x] **步骤 1：添加作品仓库、记录模型导入和失败测试**

测试建立一个 `matched`、TMDB ID 为 16907、题材为空的 `CloudWorkTmdbRecord`，并把同一 ID 放入云文件索引；向服务传入 `MemoryCloudWorkTmdbStorage`。断言详情接口只收到一次 `movie:16907`，写回记录包含 `动画`，同时标题、状态、匹配来源和规则版本保持不变。

核心断言：

```dart
expect(client.detailKeys, const <String>['movie:16907']);
final updated = (await workRepository.getAll()).single;
expect(updated.metadata!.genres, const <String>['动画']);
expect(updated.metadata!.title, '火影忍者剧场版：大活剧！雪姬忍法帖');
expect(updated.status, CloudWorkTmdbStatus.matched);
expect(updated.tmdbMatchOrigin, TmdbMatchOrigin.automatic);
expect(updated.tmdbRuleVersion, currentTmdbRuleVersion);
```

- [x] **步骤 2：运行测试并确认按预期失败**

运行：

```powershell
D:\flutter\bin\flutter.bat test test\library_genre_backfill_service_test.dart
```

预期：FAIL，原因是 `LibraryGenreBackfillService` 尚不接受或处理 `CloudWorkTmdbRepository`，而不是测试语法错误。

### 任务 3：实现作品级题材补齐

**文件：**

- 修改：`lib/modules/cloud/cloud_work_tmdb_record.dart`
- 修改：`lib/features/library/application/library_genre_backfill_service.dart`

- [x] **步骤 1：为作品记录添加保留字段的元数据替换方法**

在 `CloudWorkTmdbRecord` 中增加：

```dart
CloudWorkTmdbRecord withMetadata(TmdbMetadata value) {
  return CloudWorkTmdbRecord(
    sourceId: sourceId,
    workKey: workKey,
    workRootId: workRootId,
    workRootPath: workRootPath,
    remoteName: remoteName,
    status: status,
    checkedAt: checkedAt,
    scrapeTitleOverride: scrapeTitleOverride,
    metadata: value,
    posterCachePath: posterCachePath,
    tmdbMatchOrigin: tmdbMatchOrigin,
    tmdbRuleVersion: tmdbRuleVersion,
  );
}
```

同时在 `_metadataEquals` 和 `_metadataHash` 中加入 `genres`，避免仅题材变化的记录仍被视为相等。

- [x] **步骤 2：扩展补齐服务的依赖和目标集合**

为构造函数增加必需的 `CloudWorkTmdbRepository workRepository`。API Key 非空后读取 `getAll()`，仅收集：

```dart
record.status == CloudWorkTmdbStatus.matched &&
record.metadata != null &&
record.metadata!.id > 0 &&
record.metadata!.genres.isEmpty
```

把记录加入现有 `(mediaType, id)` 目标的 `workRecords`，因此同一作品在本地、云文件、作品记录中仍只请求一次详情。

- [x] **步骤 3：详情成功后批量写回作品记录**

对每个目标生成：

```dart
record.withMetadata(record.metadata!.copyWith(genres: details.genres))
```

循环结束后调用 `_workRepository.upsertAll(workUpdates.values)`。详情为空或请求失败时保持原记录不变，继续处理其他目标。

- [x] **步骤 4：运行回归测试并确认通过**

运行：

```powershell
D:\flutter\bin\flutter.bat test test\library_genre_backfill_service_test.dart test\cloud_work_tmdb_repository_test.dart
```

预期：PASS，且测试输出无异常或警告。

### 任务 4：接入应用共享仓库

**文件：**

- 修改：`lib/pages/local/local_controller.dart`
- 修改：`lib/app/bindings/library_bindings.dart`
- 修改：`test/local_controller_test.dart`

- [x] **步骤 1：给 LocalController 增加作品仓库依赖**

增加可选参数 `CloudWorkTmdbRepository? cloudWorkTmdbRepository`，在私有构造函数中保存为：

```dart
_cloudWorkTmdbRepository =
    cloudWorkTmdbRepository ?? CloudWorkTmdbRepository()
```

默认补齐服务构造时传入 `workRepository: _cloudWorkTmdbRepository`。测试中的 `_ControlledGenreBackfillService` 使用 `MemoryCloudWorkTmdbStorage`。

- [x] **步骤 2：在 Flutter Modular 绑定中注入共享仓库**

`LocalController` 构造调用增加：

```dart
cloudWorkTmdbRepository: Modular.get<CloudWorkTmdbRepository>(),
```

- [x] **步骤 3：运行控制器和分类相关测试**

运行：

```powershell
D:\flutter\bin\flutter.bat test test\local_controller_test.dart test\media_library_query_test.dart test\media_category_page_test.dart
```

预期：控制器和现有分类查询测试全部 PASS。

- [x] **步骤 4：提交功能修复**

```powershell
git add lib test
git commit -m "修复网盘作品动漫标签补齐"
```

### 任务 5：更新版本与用户说明

**文件：**

- 修改：`pubspec.yaml`
- 修改：`RELEASE_NOTES.md`
- 修改：`lib/utils/version_history.dart`

- [x] **步骤 1：升级版本到 2.1.153**

将 `version` 改为 `2.1.153+20153`，历史兼容 `msix_version` 同步为 `2.1.153.0`，但不生成 MSIX。

- [x] **步骤 2：添加普通用户可理解的发布说明**

说明“修复部分已正确识别的网盘动画电影只显示在电影分类、未同时显示在动漫分类的问题”。

- [x] **步骤 3：运行版本测试并提交**

```powershell
D:\flutter\bin\flutter.bat test test\version_history_current_test.dart test\windows_installer_contract_test.dart
git add pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
git commit -m "发布看影音2.1.153"
```

预期：测试 PASS，版本文件提交成功。

### 任务 6：完整验证与交付安装程序

- [ ] **步骤 1：格式化改动并检查差异**

```powershell
D:\flutter\bin\dart.bat format lib test
git diff --check
git status --short
```

预期：无格式错误、无空白错误，仅包含本轮相关文件。

- [ ] **步骤 2：运行完整测试和静态分析**

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

预期：所有测试通过；静态分析无 error。

- [ ] **步骤 3：构建 Windows Release**

```powershell
D:\flutter\bin\flutter.bat build windows --release
```

预期：退出码 0，`build\windows\x64\runner\Release\kanyingyin.exe` 产品版本为 2.1.153。

- [ ] **步骤 4：生成并复制 Inno Setup 安装器**

```powershell
powershell -ExecutionPolicy Bypass -File tool\windows\installer\build_inno_setup.ps1
```

验证生成的安装器版本和 Release 主程序版本，把安装器复制到：

```text
C:\Users\asus\Desktop\看影音-2.1.153-测试版-安装程序.exe
```

不得生成 MSIX。

- [ ] **步骤 5：计算哈希并检查最终状态**

```powershell
Get-FileHash -Algorithm SHA256 'C:\Users\asus\Desktop\看影音-2.1.153-测试版-安装程序.exe'
git status --short
git log -3 --oneline
```

预期：安装器存在且哈希可读；工作区干净；本轮功能和版本提交均存在。
