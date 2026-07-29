# Scraped Metadata Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为看影音增加 `.kyymeta` 刮削资料迁移包，让另一台设备在重新扫描同一批本地和个人网盘视频后，无需访问 TMDB 即可恢复已确认资料和离线图片。

**Architecture:** 在 `features/scraped_metadata_transfer` 下建立领域模型、ZIP 编解码、导出器、只读导入规划器和可回滚导入器。迁移服务只通过现有仓库接口读取和覆盖刮削字段，UI 负责文件选择、来源映射、预览和确认，不复制媒体索引或任何凭据。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、Hive CE、`archive`、`crypto`、`file_picker`、`flutter_cache_manager`、`path_provider`、`flutter_test`

---

## 文件结构

新增文件：

- `lib/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart`：迁移清单、可移植本地/网盘记录、导入规划和结果的强类型模型。
- `lib/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart`：流式 ZIP 写入、安全解包、版本和 SHA-256 校验。
- `lib/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart`：从现有仓库筛选已匹配记录、转换相对身份并收集缓存图片。
- `lib/features/scraped_metadata_transfer/application/scraped_metadata_import_planner.dart`：自动映射来源和媒体，生成不写数据的预览。
- `lib/features/scraped_metadata_transfer/application/scraped_metadata_importer.dart`：覆盖刮削字段、安装图片、失败回滚。
- `lib/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart`：组合编解码、导出、预览和导入流程，供页面调用。
- `lib/features/scraped_metadata_transfer/presentation/scraped_metadata_transfer_page.dart`：导出、导入、根目录映射、确认和汇总界面。
- `test/scraped_metadata_transfer_models_test.dart`
- `test/scraped_metadata_archive_codec_test.dart`
- `test/scraped_metadata_exporter_test.dart`
- `test/scraped_metadata_import_planner_test.dart`
- `test/scraped_metadata_importer_test.dart`
- `test/scraped_metadata_transfer_page_test.dart`

修改文件：

- `lib/repositories/local_media_index_repository.dart`：增加原子批量更新接口。
- `lib/repositories/cloud_resource_tmdb_repository.dart`：公开全量读取和全量替换接口。
- `lib/repositories/cloud_work_tmdb_repository.dart`：公开全量读取和全量替换接口。
- `lib/repositories/cloud_series_match_rule_repository.dart`：公开全量读取和全量替换接口。
- `lib/modules/cloud/cloud_resource_tmdb_record.dart`：增加重绑定来源和图片路径的强类型复制方法。
- `lib/modules/cloud/cloud_work_tmdb_record.dart`：增加重绑定来源、作品身份和图片路径的强类型复制方法。
- `lib/modules/cloud/cloud_series_match_rule.dart`：增加重绑定来源和图片路径的强类型复制方法。
- `lib/app/bindings/library_bindings.dart`：注册迁移服务依赖。
- `lib/pages/settings/settings_module.dart`：注册迁移页路由。
- `lib/pages/settings/tmdb_settings.dart`：增加“刮削资料迁移”入口。
- `lib/core/app_version.dart`、`pubspec.yaml`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：更新 `2.1.93` 交付版本。

## Task 1：建立版本化迁移领域模型

**Files:**

- Create: `lib/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart`
- Test: `test/scraped_metadata_transfer_models_test.dart`

- [ ] **Step 1: 写入失败测试**

测试必须构造一个包含中文标题、一个本地来源、一个网盘来源和一个图片条目的 `ScrapedMetadataPayload`，验证：

```dart
test('迁移数据使用版本 1 往返且不序列化旧设备图片绝对路径', () {
  final payload = transferPayloadFixture();
  final restored = ScrapedMetadataPayload.fromJson(payload.toJson());

  expect(restored.formatVersion, 1);
  expect(restored.localSources.single.records.single.tmdb['title'], '三体');
  expect(restored.cloudSources.single.type, CloudSourceType.quark);
  expect(jsonEncode(restored.toJson()), isNot(contains(r'C:\cache')));
  expect(
    restored.localSources.single.records.single.posterImage,
    'images/abc.jpg',
  );
});
```

同时测试缺少 `formatVersion`、`relativePath` 为空、文件大小为负数和超过 100,000 条记录时抛出 `FormatException`。

- [ ] **Step 2: 运行测试并确认因类型不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_models_test.dart
```

Expected: FAIL，提示 `ScrapedMetadataPayload` 或关联类型未定义。

- [ ] **Step 3: 实现最小强类型模型**

实现以下公开 API，所有 `fromJson` 在构造前完成必填字段、数量和枚举校验：

```dart
const scrapedMetadataFormat = 'kanyingyin-scraped-metadata';
const scrapedMetadataFormatVersion = 1;
const maxTransferRecords = 100000;
const maxTransferImages = 20000;

final class ScrapedMetadataPayload {
  const ScrapedMetadataPayload({
    required this.formatVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.localSources,
    required this.cloudSources,
  });

  final int formatVersion;
  final DateTime exportedAt;
  final String appVersion;
  final List<PortableLocalSource> localSources;
  final List<PortableCloudSource> cloudSources;

  int get recordCount =>
      localSources.fold(0, (sum, value) => sum + value.records.length) +
      cloudSources.fold(0, (sum, value) => sum + value.recordCount);

  factory ScrapedMetadataPayload.fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson();
}
```

同文件定义：

- `PortableLocalSource(exportId, name, originalRoot, records)`
- `PortableLocalRecord(relativePath, size, tmdb, scrapeStatus, tmdbMatchOrigin, tmdbRuleVersion, titleLocked, posterLocked, overviewLocked, manualOverride, posterImage)`
- `PortableCloudSource(exportId, type, name, sanitizedBaseUrl, roots, resourceRecords, workRecords, seriesRules)`
- `PortableCloudResourceRecord(recordJson, posterImage, seasonImages)`
- `PortableCloudWorkRecord(recordJson, posterImage, seasonImages)`
- `PortableCloudSeriesRule(ruleJson, posterImage, seasonImages)`
- `PortableImageEntry(path, length, sha256)`
- `ScrapedMetadataManifest(format, formatVersion, appVersion, exportedAt, localRecordCount, cloudRecordCount, images, dataFiles)`
- `LocalSourceMapping(exportSourceId, targetSourceId)`
- `CloudSourceMapping(exportSourceId, targetSourceId)`
- `ScrapedMetadataImportPlan(payload, localMappings, cloudMappings, localMatches, cloudResourceMatches, cloudWorkMatches, unresolvedLocalSources, unresolvedCloudSources, missingMediaCount, recoverableImageCount)`
- `ScrapedMetadataTransferResult(localCount, cloudCount, imageCount, skippedCount)`

`tmdb` 和已有网盘记录使用 `Map<String, Object?>` 保存已公开的 `toJson()` 结果，避免在迁移领域层复制 TMDB 模型。`toJson()` 必须只输出包内图片路径，不允许输出缓存绝对路径。

- [ ] **Step 4: 运行模型测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_models_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart test/scraped_metadata_transfer_models_test.dart
git commit -m "功能：定义刮削资料迁移格式"
```

## Task 2：实现安全的 `.kyymeta` 编解码

**Files:**

- Create: `lib/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart`
- Test: `test/scraped_metadata_archive_codec_test.dart`

- [ ] **Step 1: 写入编解码和恶意包失败测试**

测试使用临时目录，写入一张图片和一个最小 payload，验证包中只包含 `manifest.json`、`local.json`、`cloud.json` 和 `images/<sha256>.jpg`，随后解码并比较内容。另行构造以下包并断言 `FormatException`：

```dart
for (final name in <String>[
  '../outside.jpg',
  '/absolute.jpg',
  r'C:\absolute.jpg',
  'images/../outside.jpg',
]) {
  expect(
    () => codec.read(maliciousArchive(name)),
    throwsA(isA<FormatException>()),
  );
}
```

再覆盖未知格式版本、重复归一化路径、符号链接、哈希不一致、单图片声明超过 25 MiB、总声明超过 10 GiB 和图片数超过 20,000。

- [ ] **Step 2: 运行测试并确认因编解码器不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_archive_codec_test.dart
```

Expected: FAIL，提示 `ScrapedMetadataArchiveCodec` 未定义。

- [ ] **Step 3: 实现流式写入和安全读取**

公开 API：

```dart
typedef TransferTemporaryDirectoryProvider = Future<Directory> Function();

final class DecodedScrapedMetadataArchive {
  const DecodedScrapedMetadataArchive({
    required this.payload,
    required this.imageFiles,
    required this.temporaryDirectory,
  });

  final ScrapedMetadataPayload payload;
  final Map<String, File> imageFiles;
  final Directory temporaryDirectory;

  Future<void> dispose() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

final class ScrapedMetadataArchiveCodec {
  ScrapedMetadataArchiveCodec({
    TransferTemporaryDirectoryProvider? temporaryDirectoryProvider,
  });

  Future<File> write({
    required File output,
    required ScrapedMetadataPayload payload,
    required Map<String, File> images,
  });

  Future<DecodedScrapedMetadataArchive> read(File input);
}
```

写入时先在临时目录生成 UTF-8 JSON 文件，流式计算数据文件和图片 SHA-256，再使用 `ZipFileEncoder` 写入临时 `.partial` 文件；关闭成功后重命名为用户目标。读取时使用 `InputFileStream` 和 `ZipDecoder().decodeStream(..., storeData: false)`，先验证所有条目名称：

```dart
bool isSafeArchivePath(String value) {
  final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
  return value.isNotEmpty &&
      !p.posix.isAbsolute(normalized) &&
      !RegExp(r'^[A-Za-z]:').hasMatch(normalized) &&
      normalized != '..' &&
      !normalized.startsWith('../') &&
      normalized == value.replaceAll('\\', '/');
}
```

拒绝链接和重复路径；逐条写到临时目录时累计实际解压字节并执行上限检查。完成后校验 manifest 中每个文件的长度和 SHA-256，再解析 `local.json` 与 `cloud.json` 合成 payload。任何异常都删除临时目录和 `.partial` 文件。

- [ ] **Step 4: 运行编解码测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_archive_codec_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart test/scraped_metadata_archive_codec_test.dart
git commit -m "功能：实现安全刮削资料迁移包"
```

## Task 3：补充仓库批量读写和记录重绑定能力

**Files:**

- Modify: `lib/repositories/local_media_index_repository.dart`
- Modify: `lib/repositories/cloud_resource_tmdb_repository.dart`
- Modify: `lib/repositories/cloud_work_tmdb_repository.dart`
- Modify: `lib/repositories/cloud_series_match_rule_repository.dart`
- Modify: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_work_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_series_match_rule.dart`
- Test: `test/scraped_metadata_repository_contract_test.dart`

- [ ] **Step 1: 写入失败测试**

测试内存存储验证：

```dart
test('批量替换可用于导入提交和回滚', () async {
  final repository = CloudResourceTmdbRepository(
    storage: MemoryCloudResourceTmdbStorage(),
  );
  await repository.replaceAll(<CloudResourceTmdbRecord>[oldRecord]);
  expect(await repository.getAll(), <CloudResourceTmdbRecord>[oldRecord]);
  await repository.replaceAll(<CloudResourceTmdbRecord>[newRecord]);
  expect(await repository.getAll(), <CloudResourceTmdbRecord>[newRecord]);
});

test('重绑定网盘记录只改变来源身份和图片路径', () {
  final rebound = oldRecord.rebindForTransfer(
    sourceId: 'new-source',
    remoteId: 'new-id',
    remotePath: '/影视/三体',
    posterCachePath: r'C:\new-cache\poster.jpg',
    seasons: restoredSeasons,
  );
  expect(rebound.sourceId, 'new-source');
  expect(rebound.tmdbId, oldRecord.tmdbId);
  expect(rebound.customTitle, oldRecord.customTitle);
});
```

本地仓库测试 `updateItems(Map<String, LocalMediaIndexItem>)` 一次写入多个索引项，并保留未命中项。

- [ ] **Step 2: 运行测试并确认因接口不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_repository_contract_test.dart
```

Expected: FAIL，提示 `getAll`、`replaceAll`、`updateItems` 或 `rebindForTransfer` 不存在。

- [ ] **Step 3: 实现最小批量接口**

在 `ILocalMediaIndexRepository` 增加：

```dart
Future<void> updateItems(Map<String, LocalMediaIndexItem> itemsById);
```

实现中读取一次 `getAll()`，按 `item.id` 替换，随后调用一次 `_save`。

三个网盘刮削仓库都增加：

```dart
Future<List<RecordType>> getAll() => _getAll();

Future<void> replaceAll(Iterable<RecordType> replacements) =>
    _mutationLock.synchronized(
      () => _write(replacements.toList(growable: false)),
    );
```

系列规则仓库使用其现有 `_lock`。三个记录模型增加 `rebindForTransfer`，完整复制原 TMDB 和用户覆盖字段，只接收当前设备的新来源身份、资源身份、海报路径和已重写的季度列表。

- [ ] **Step 4: 运行相关仓库测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_repository_contract_test.dart test\cloud_resource_tmdb_repository_test.dart test\cloud_work_tmdb_repository_test.dart test\cloud_series_match_rule_repository_test.dart test\local_media_index_repository_cache_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/repositories lib/modules/cloud test/scraped_metadata_repository_contract_test.dart
git commit -m "功能：支持批量恢复刮削资料"
```

## Task 4：实现刮削资料导出器

**Files:**

- Create: `lib/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart`
- Test: `test/scraped_metadata_exporter_test.dart`

- [ ] **Step 1: 写入失败测试**

使用内存仓库准备：

- 两条本地记录，仅一条 `scrapeStatus == matched && tmdb != null`。
- 一个夸克来源及一个 OpenList 来源。
- matched/unmatched 网盘单资源、整部作品和系列规则。
- 两个内容相同但路径不同的海报文件。
- `CachedImageLookup` 返回一张已缓存背景图。

断言：

```dart
expect(result.payload.localSources.single.records, hasLength(1));
expect(result.payload.cloudSources, hasLength(2));
expect(result.images, hasLength(2), reason: '相同海报按 SHA-256 去重');
final encoded = jsonEncode(result.payload.toJson());
expect(encoded, isNot(contains('password')));
expect(encoded, isNot(contains('accessToken')));
expect(encoded, isNot(contains('tmdbApiKey')));
expect(encoded, isNot(contains(r'C:\cache')));
```

OpenList 地址断言移除 `user:pass@`、查询参数和 fragment。

- [ ] **Step 2: 运行测试并确认因导出器不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_exporter_test.dart
```

Expected: FAIL，提示 `ScrapedMetadataExporter` 未定义。

- [ ] **Step 3: 实现导出器**

公开 API：

```dart
abstract interface class CachedImageLookup {
  Future<File?> find(String url);
}

final class FlutterCachedImageLookup implements CachedImageLookup {
  @override
  Future<File?> find(String url) async =>
      (await DefaultCacheManager().getFileFromCache(url))?.file;
}

final class ScrapedMetadataExportDraft {
  const ScrapedMetadataExportDraft({
    required this.payload,
    required this.images,
    required this.skippedCount,
  });

  final ScrapedMetadataPayload payload;
  final Map<String, File> images;
  final int skippedCount;
}

final class ScrapedMetadataExporter {
  Future<ScrapedMetadataExportDraft> build();
}
```

构造器注入本地索引、本地来源、网盘来源、网盘三类刮削仓库、`CachedImageLookup` 和当前版本/时钟。仅导出明确 matched 且 TMDB ID 大于 0 的记录。Windows 文件来源使用 `p.relative(item.path, from: source.path)`，拒绝结果位于 `..` 之外；Android 文档来源使用 `MediaLocation` 的稳定相对标识。

图片收集顺序为显式 `posterCachePath`/本地 `cover`、季度 `posterCachePath`、`posterUrl` 的现有通用缓存、`backdropUrl` 的现有通用缓存。绝不联网下载。每个文件流式计算 SHA-256，生成 `images/<hash><安全扩展名>`，相同哈希只保留一份。

- [ ] **Step 4: 运行导出器测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_exporter_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart test/scraped_metadata_exporter_test.dart
git commit -m "功能：导出本地与网盘刮削资料"
```

## Task 5：实现跨盘符和跨来源导入规划

**Files:**

- Create: `lib/features/scraped_metadata_transfer/application/scraped_metadata_import_planner.dart`
- Test: `test/scraped_metadata_import_planner_test.dart`

- [ ] **Step 1: 写入失败测试**

覆盖四个行为：

```dart
test('本地盘符变化后按相对路径和大小匹配', () async {
  final plan = await planner.plan(
    payload,
    localOverrides: {'old-local': r'E:\媒体\影视'},
  );
  expect(plan.localMatches, hasLength(1));
  expect(plan.localMatches.single.target.path, r'E:\媒体\影视\三体\S01E01.mkv');
});

test('同相对路径但大小变化时不匹配', () async {
  final plan = await planner.plan(sizeChangedPayload);
  expect(plan.localMatches, isEmpty);
  expect(plan.missingMediaCount, 1);
});

test('网盘来源 ID 变化后按类型和根目录映射', () async {
  final plan = await planner.plan(cloudPayload);
  expect(plan.cloudMappings.single.targetSourceId, 'new-source-id');
});

test('同类型同根目录出现两个候选时保持未解决', () async {
  final plan = await ambiguousPlanner.plan(cloudPayload);
  expect(plan.unresolvedCloudSources, ['export-source-id']);
});
```

再测试远程 ID 变化时同来源内按规范化路径回退、不同来源绝不交叉匹配、OpenList 服务地址规范化比较。

- [ ] **Step 2: 运行测试并确认因规划器不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_import_planner_test.dart
```

Expected: FAIL，提示 `ScrapedMetadataImportPlanner` 未定义。

- [ ] **Step 3: 实现只读规划器**

公开 API：

```dart
final class ScrapedMetadataImportPlanner {
  ScrapedMetadataImportPlanner({
    required ILocalMediaSourceRepository localSourceRepository,
    required ILocalMediaIndexRepository localIndexRepository,
    required CloudSourceRepository cloudSourceRepository,
    required CloudMediaIndexRepository cloudIndexRepository,
  });

  Future<ScrapedMetadataImportPlan> plan(
    ScrapedMetadataPayload payload, {
    Map<String, String> localOverrides = const {},
  });
}
```

本地自动来源评分：

- 原根路径稳定 ID 相同：直接匹配。
- 否则对每个当前来源计算迁移记录中“相对路径存在且大小相同”的覆盖率。
- 覆盖率至少 80%、至少命中 1 条且严格高于第二名才自动匹配。
- 其他来源进入 `unresolvedLocalSources`，等待页面调用 `LocalDirectoryPickerPage.pick` 后以 `localOverrides` 重新规划。

网盘来源先比较类型，再比较根目录远程 ID 集合；无 ID 时比较规范化根路径集合，OpenList 同时比较移除凭据、query、fragment 后的 `scheme + host + port + path`。媒体按远程 ID 和路径共同匹配，ID 不同才在同来源内按路径回退。整部作品使用当前 `CloudMediaIndexItem.workRootId/workRootPath/workKey` 生成映射。

- [ ] **Step 4: 运行规划器测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_import_planner_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/application/scraped_metadata_import_planner.dart test/scraped_metadata_import_planner_test.dart
git commit -m "功能：规划跨设备刮削资料匹配"
```

## Task 6：实现覆盖提交、图片安装和失败回滚

**Files:**

- Create: `lib/features/scraped_metadata_transfer/application/scraped_metadata_importer.dart`
- Test: `test/scraped_metadata_importer_test.dart`

- [ ] **Step 1: 写入失败测试**

测试目标本地项目包含不同 TMDB 结果、字幕路径、时长和索引时间。导入后断言 TMDB 和锁定字段来自迁移包，但路径、字幕、时长和索引时间不变。网盘记录断言旧 `sourceId` 被重写，目标仓库已有记录被覆盖。

注入一个在网盘整部作品写入时抛错的存储，断言：

```dart
await expectLater(importer.apply(plan, archive), throwsA(isA<FileSystemException>()));
expect(localRepository.getAll(), originalLocalItems);
expect(await resourceRepository.getAll(), originalResourceRecords);
expect(await workRepository.getAll(), originalWorkRecords);
expect(await ruleRepository.getAll(), originalRules);
expect(await importedImage.exists(), isFalse);
```

- [ ] **Step 2: 运行测试并确认因导入器不存在而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_importer_test.dart
```

Expected: FAIL，提示 `ScrapedMetadataImporter` 未定义。

- [ ] **Step 3: 实现导入器**

公开 API：

```dart
typedef TransferCacheRootProvider = Future<Directory> Function();

final class ScrapedMetadataImporter {
  ScrapedMetadataImporter({
    required ILocalMediaIndexRepository localIndexRepository,
    required CloudResourceTmdbRepository resourceRepository,
    required CloudWorkTmdbRepository workRepository,
    required CloudSeriesMatchRuleRepository ruleRepository,
    TransferCacheRootProvider? cacheRootProvider,
  });

  Future<ScrapedMetadataTransferResult> apply(
    ScrapedMetadataImportPlan plan,
    DecodedScrapedMetadataArchive archive,
  );
}
```

缓存根目录使用 `getApplicationSupportDirectory()/kanyingyin/scraped_metadata`，图片目标以 SHA-256 命名。先把全部待用图片复制到同目录 `.staging-<时间>`，然后保存四个仓库完整快照。使用：

```dart
target.copyWith(
  tmdb: TmdbMetadata.fromJson(portable.tmdb),
  titleLocked: portable.titleLocked,
  posterLocked: portable.posterLocked,
  overviewLocked: portable.overviewLocked,
  scrapeStatus: TmdbScrapeStatus.matched,
  tmdbMatchOrigin: parsedOrigin,
  tmdbRuleVersion: portable.tmdbRuleVersion,
  manualOverride: portable.manualOverride,
  cover: installedPosterPath ?? target.cover,
)
```

提交顺序为本地、网盘单资源、网盘作品、系列规则。任一步抛错时按相反顺序 `replaceAll`/`updateItems` 恢复快照，删除本轮新图片；恢复失败记录到日志后仍抛出包含原始错误的 `ScrapedMetadataImportException`。成功后删除 staging 和不再需要的备份，不修改用户原始媒体。

- [ ] **Step 4: 运行导入器及仓库测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_importer_test.dart test\scraped_metadata_repository_contract_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/application/scraped_metadata_importer.dart test/scraped_metadata_importer_test.dart
git commit -m "功能：恢复并回滚刮削资料"
```

## Task 7：组合迁移服务并接入依赖注入

**Files:**

- Create: `lib/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart`
- Modify: `lib/app/bindings/library_bindings.dart`
- Test: `test/scraped_metadata_transfer_service_test.dart`

- [ ] **Step 1: 写入服务流程失败测试**

测试 `exportTo(File)` 调用导出器和 codec，`inspect(File)` 返回 archive + plan，`apply(session)` 调用导入器并始终清理临时目录。取消导入调用 `session.dispose()` 后也必须清理。

- [ ] **Step 2: 运行测试并确认服务不存在**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_service_test.dart
```

Expected: FAIL，提示 `ScrapedMetadataTransferService` 未定义。

- [ ] **Step 3: 实现服务和注册**

服务 API：

```dart
final class ScrapedMetadataImportSession {
  ScrapedMetadataImportSession({
    required this.archive,
    required this.plan,
  });

  final DecodedScrapedMetadataArchive archive;
  ScrapedMetadataImportPlan plan;

  Future<void> dispose() => archive.dispose();
}

final class ScrapedMetadataTransferService {
  Future<ScrapedMetadataTransferResult> exportTo(File output);
  Future<ScrapedMetadataImportSession> inspect(File input);
  Future<void> remapLocal(
    ScrapedMetadataImportSession session,
    String exportSourceId,
    String targetRoot,
  );
  Future<ScrapedMetadataTransferResult> apply(
    ScrapedMetadataImportSession session,
  );
}
```

在 `registerLibraryBindings` 中用已有单例仓库组合 exporter、planner、importer 和 codec，并注册 `ScrapedMetadataTransferService`。不注入 `CloudCredentialStore`，从依赖边界上保证迁移功能无法读取凭据。

- [ ] **Step 4: 运行服务和绑定测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_service_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart lib/app/bindings/library_bindings.dart test/scraped_metadata_transfer_service_test.dart
git commit -m "功能：接入刮削资料迁移服务"
```

## Task 8：实现设置页入口和导入导出界面

**Files:**

- Create: `lib/features/scraped_metadata_transfer/presentation/scraped_metadata_transfer_page.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/settings/tmdb_settings.dart`
- Test: `test/scraped_metadata_transfer_page_test.dart`
- Modify: `test/tmdb_settings_language_test.dart`

- [ ] **Step 1: 写入组件失败测试**

测试注入假服务，验证：

- 页面存在 `export-scraped-metadata` 和 `import-scraped-metadata` 两个按钮。
- 导入预览显示“将覆盖”“未找到”“来源未配置”数量。
- 未解决本地来源显示“选择当前目录”按钮。
- 点击取消会 dispose session，点击确认才调用 apply。
- TMDB 设置页显示“刮削资料迁移”入口。

核心断言：

```dart
expect(find.text('刮削资料迁移'), findsOneWidget);
expect(find.byKey(const ValueKey('export-scraped-metadata')), findsOneWidget);
expect(find.byKey(const ValueKey('import-scraped-metadata')), findsOneWidget);
expect(fakeService.applyCount, 0);
await tester.tap(find.text('确认导入'));
await tester.pumpAndSettle();
expect(fakeService.applyCount, 1);
```

- [ ] **Step 2: 运行测试并确认页面不存在**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_page_test.dart test\tmdb_settings_language_test.dart
```

Expected: FAIL，提示页面、路由或文本不存在。

- [ ] **Step 3: 实现页面和路由**

页面保持现有 `KSettingsScaffold`、`KSettingsSection` 和 `KSettingsTile` 层级：

- 导出使用 `FilePicker.saveFile(dialogTitle: '导出刮削资料', fileName: defaultName, allowedExtensions: ['kyymeta'], type: FileType.custom)`。
- 导入使用 `FilePicker.pickFiles(dialogTitle: '导入刮削资料', allowedExtensions: ['kyymeta'], type: FileType.custom, allowMultiple: false)`。
- 本地来源映射使用 `LocalDirectoryPickerPage.pick(context, initialPath: ...)`，不直接调用平台文件夹选择器。
- 操作期间禁用按钮并显示 `CircularProgressIndicator`。
- 预览使用确认对话框，明确写出“将覆盖目标设备同一媒体的现有刮削资料，不会修改视频或网盘文件”。
- 完成 SnackBar 显示本地、网盘、图片和跳过数量；错误映射为中文消息。

在 `SettingsModule` 增加 `/tmdb/transfer` 路由并注入 `Modular.get<ScrapedMetadataTransferService>()`。在 `TmdbSettingsPage` 的缓存清理项之前增加导航 tile，点击 `Modular.to.pushNamed('/settings/tmdb/transfer')`。

- [ ] **Step 4: 运行页面测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_page_test.dart test\tmdb_settings_language_test.dart test\settings_hub_page_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/features/scraped_metadata_transfer/presentation/scraped_metadata_transfer_page.dart lib/pages/settings/settings_module.dart lib/pages/settings/tmdb_settings.dart test/scraped_metadata_transfer_page_test.dart test/tmdb_settings_language_test.dart
git commit -m "功能：增加刮削资料迁移界面"
```

## Task 9：版本、用户文案和完整验证

**Files:**

- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Test: `test/version_history_current_test.dart`

- [ ] **Step 1: 再次记录安装前 Windows 版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName | Format-List
```

Expected: 在交付记录中保留当前结果；本轮开始时已记录为 `2.1.92.0`，若此时发生变化，以新查询为准并说明。

- [ ] **Step 2: 写入版本失败测试并更新用户文案**

先把 `test/version_history_current_test.dart` 预期改为 `2.1.93`，运行并确认失败。随后更新：

```yaml
version: 2.1.93+20193
msix_config:
  msix_version: 2.1.93.0
```

`AppVersion.current` 改为 `2.1.93`。在版本历史和发布说明顶部加入面向用户的文案：

- 可把本地与个人网盘已经确认的 TMDB 标题、简介、评分、海报、背景图和季度资料导出为迁移包。
- 新设备重新添加并扫描同一批资源后，可离线导入并覆盖同一媒体的刮削资料，无需再次请求 TMDB。
- 本地盘符或媒体根目录变化时可重新映射；网盘需先登录并配置相同来源。
- 迁移包不包含视频、字幕、账号密码、Cookie、令牌或 TMDB Key，也不会修改原始媒体。

- [ ] **Step 3: 运行专项测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\scraped_metadata_transfer_models_test.dart test\scraped_metadata_archive_codec_test.dart test\scraped_metadata_exporter_test.dart test\scraped_metadata_import_planner_test.dart test\scraped_metadata_importer_test.dart test\scraped_metadata_transfer_service_test.dart test\scraped_metadata_transfer_page_test.dart test\version_history_current_test.dart
```

Expected: PASS，0 failures。

- [ ] **Step 4: 运行全量测试和静态分析**

Run:

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: 全部测试 PASS；分析输出 `No issues found!`。

- [ ] **Step 5: 构建 Windows Release**

Run:

```powershell
D:\flutter\bin\flutter.bat build windows --release
```

Expected: exit code 0，生成 `build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 6: 生成并验证 MSIX**

按项目现有私有交付方式传入证书路径和密码环境变量，执行：

```powershell
D:\flutter\bin\flutter.bat pub run msix:create
```

Expected: exit code 0，生成 `.msix`。解压或读取 `AppxManifest.xml`，确认 Identity 为 `com.kanyingyin.player`、Version 为 `2.1.93.0`。

- [ ] **Step 7: 复制安装包到桌面并核对**

将最终包复制为：

```text
C:\Users\asus\Desktop\看影音-2.1.93.msix
```

计算 SHA-256 并记录文件大小。若执行安装，再运行：

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName | Format-List
```

Expected: 安装后版本为 `2.1.93.0`；若未执行安装，明确记录“未安装，仅验证安装包版本”。

- [ ] **Step 8: 最终检查并提交**

Run:

```powershell
git status --short
git diff --check
git diff --stat
```

只暂存本轮相关文件，复核关键 diff 后提交：

```powershell
git add pubspec.yaml RELEASE_NOTES.md lib test
git commit -m "发布：支持刮削资料跨设备迁移"
```

Expected: 提交成功，工作区无本轮未提交改动。

## 最终人工验收

- [ ] 设备 A 导出包含本地、夸克、百度、OpenList、迅雷刮削资料和图片的 `.kyymeta`。
- [ ] 设备 B 在不同本地盘符下扫描同一批文件并完成目录映射。
- [ ] 设备 B 先登录并扫描相同网盘来源，然后在断网、无 TMDB Key 状态下导入。
- [ ] 标题、简介、评分、海报、背景图、季度海报、手动名称和锁定状态恢复。
- [ ] 目标设备同一媒体旧刮削结果被覆盖，未匹配媒体没有被错误套用。
- [ ] 视频、字幕、网盘文件和账号凭据未被修改或写入迁移包。
