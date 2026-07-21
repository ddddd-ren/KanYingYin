# 日志与缓存可靠性 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一日志控制台与文件脱敏、让日志页面读取真实轮转日志，并可靠处理缓存统计和清理异常。

**Architecture:** `AppLogOutput` 只生成一次脱敏行并复用于控制台和文件；`LogArchiveReader` 封装轮转日志读取与清理；`LocalImageCacheService` 封装缓存目录、容量统计和删除，页面只负责状态和反馈。

**Tech Stack:** Flutter 3.41.9、Dart 3.11.5、flutter_test、dart:io、现有 `RotatingLogWriter` 与 `LogSanitizer`。

---

## 文件结构

- 修改 `lib/utils/logger.dart`：统一控制台与文件脱敏。
- 新建 `lib/utils/log_archive_reader.dart`：读取、合并和清理轮转日志。
- 修改 `lib/pages/logs/logs_page.dart`：通过读取器获取日志。
- 新建 `lib/services/local_image_cache_service.dart`：统计和清理图片缓存。
- 修改 `lib/pages/about/about_page.dart`：等待缓存清理并反馈结果。
- 修改 `test/logger_pipeline_test.dart`。
- 新建 `test/log_archive_reader_test.dart`。
- 新建 `test/local_image_cache_service_test.dart`。

### Task 1: 统一日志脱敏输出

**Files:**
- Modify: `test/logger_pipeline_test.dart`
- Modify: `lib/utils/logger.dart:114-131`

- [ ] **Step 1: 写入控制台脱敏失败测试**

在 `test/logger_pipeline_test.dart` 增加：

```dart
test('控制台与文件使用相同脱敏日志', () async {
  final tempDir = await Directory.systemTemp.createTemp('logger_console_');
  addTearDown(() => tempDir.delete(recursive: true));
  final writer = RotatingLogWriter(
    directoryProvider: () async => tempDir,
    maxBytes: 1024 * 1024,
  );
  final output = AppLogOutput(writer: writer);
  final printed = <String>[];

  runZoned(
    () => output.output(OutputEvent(
      LogEvent(Level.info, 'ignored'),
      const <String>[
        '\x1B[32mGET https://drive.example.com/private/a.mkv?token=secret\x1B[0m',
      ],
    )),
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => printed.add(line),
    ),
  );
  await output.flush();

  expect(printed.single, 'GET https://drive.example.com');
  final file = File(
    '${tempDir.path}${Platform.pathSeparator}${RotatingLogWriter.activeFileName}',
  );
  final content = await file.readAsString();
  expect(content, contains(printed.single));
  expect(content, isNot(contains('secret')));
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

```powershell
D:\flutter\bin\flutter.bat test test/logger_pipeline_test.dart --plain-name "控制台与文件使用相同脱敏日志"
```

预期：FAIL，控制台仍包含 URL 路径、查询参数或 ANSI 控制码。

- [ ] **Step 3: 实现单次脱敏并复用结果**

将 `AppLogOutput` 的输出核心改为：

```dart
@override
void output(OutputEvent event) {
  final sanitizedLines = event.lines
      .map((line) => _sanitizer.sanitize(_removeAnsiCodes(line)))
      .toList(growable: false);
  for (final line in sanitizedLines) {
    print(line);
  }
  _writeToFile(event.level, sanitizedLines);
}

void _writeToFile(Level level, List<String> lines) {
  final buffer = StringBuffer()
    ..writeln(
      '[${DateTime.now().toIso8601String()}] ${level.name.toUpperCase()}',
    );
  for (final line in lines) {
    buffer.writeln(line);
  }
  unawaited(_writer.write(buffer.toString().trimRight()));
}
```

- [ ] **Step 4: 运行日志测试**

```powershell
D:\flutter\bin\flutter.bat test test/logger_pipeline_test.dart test/log_sanitizer_test.dart test/rotating_log_writer_test.dart
```

预期：PASS，0 failures。

- [ ] **Step 5: 提交**

```powershell
git add lib/utils/logger.dart test/logger_pipeline_test.dart
git commit -m "修复日志控制台脱敏"
```

### Task 2: 统一日志页面的数据来源

**Files:**
- Create: `lib/utils/log_archive_reader.dart`
- Create: `test/log_archive_reader_test.dart`
- Modify: `lib/pages/logs/logs_page.dart`

- [ ] **Step 1: 写入轮转日志读取与清理失败测试**

创建 `test/log_archive_reader_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/log_archive_reader.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

void main() {
  test('读取真实活动日志和轮转日志并可统一清理', () async {
    final root = await Directory.systemTemp.createTemp('log_archive_');
    addTearDown(() => root.delete(recursive: true));
    final writer = RotatingLogWriter(
      directoryProvider: () async => root,
      maxBytes: 12,
      maxFiles: 4,
    );
    await writer.write('第一条较长日志');
    await writer.write('第二条较长日志');
    final reader = LogArchiveReader(writer: writer);

    final content = await reader.readAll();
    expect(content, contains('第一条较长日志'));
    expect(content, contains('第二条较长日志'));
    await reader.clear();
    expect(await writer.listLogFiles(), isEmpty);
  });

  test('没有日志文件时返回空内容', () async {
    final root = await Directory.systemTemp.createTemp('log_archive_empty_');
    addTearDown(() => root.delete(recursive: true));
    final writer = RotatingLogWriter(directoryProvider: () async => root);
    expect(await LogArchiveReader(writer: writer).readAll(), isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试并确认缺少实现**

```powershell
D:\flutter\bin\flutter.bat test test/log_archive_reader_test.dart
```

预期：FAIL，找不到 `LogArchiveReader`。

- [ ] **Step 3: 实现日志归档读取器**

创建 `lib/utils/log_archive_reader.dart`：

```dart
import 'dart:io';

import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/rotating_log_writer.dart';

class LogArchiveReader {
  LogArchiveReader({RotatingLogWriter? writer})
      : _writer = writer ?? AppLogOutput.sharedWriter;

  final RotatingLogWriter _writer;

  Future<String> readAll() async {
    await _writer.flush();
    final contents = <String>[];
    for (final file in await _writer.listLogFiles()) {
      try {
        final content = await file.readAsString();
        if (content.isNotEmpty) contents.add(content);
      } on FileSystemException {
        // 日志可能在读取期间轮转，跳过已移动的文件。
      }
    }
    return contents.join('\n');
  }

  Future<void> clear() async {
    await _writer.flush();
    for (final file in await _writer.listLogFiles()) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 文件可能已在轮转或并发清理中删除。
      }
    }
  }
}
```

- [ ] **Step 4: 让日志页面使用读取器**

为 `LogsPage` 增加可注入读取器，并删除 `_getLogsFile` 和 `path_provider` 导入：

```dart
class LogsPage extends StatefulWidget {
  const LogsPage({super.key, this.reader});

  final LogArchiveReader? reader;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

late final LogArchiveReader _reader;

@override
void initState() {
  super.initState();
  _reader = widget.reader ?? LogArchiveReader();
  _loadLogs();
  _scrollController.addListener(_onScroll);
}
```

`_loadLogs` 的数据读取替换为：

```dart
final content = await _reader.readAll();
if (!mounted) return;
_allLines = content.isEmpty ? <String>[] : content.split('\n');
_fullContent = content;
```

`_clearLogs` 的文件操作替换为：

```dart
await _reader.clear();
if (!mounted) return;
setState(() {
  _logLines.clear();
  _allLines.clear();
  _fullContent = '';
  _displayedLines = 0;
});
```

- [ ] **Step 5: 运行日志相关测试**

```powershell
D:\flutter\bin\flutter.bat test test/log_archive_reader_test.dart test/logger_pipeline_test.dart test/log_settings_ui_test.dart
```

预期：PASS，0 failures。

- [ ] **Step 6: 提交**

```powershell
git add lib/utils/log_archive_reader.dart lib/pages/logs/logs_page.dart test/log_archive_reader_test.dart
git commit -m "修复日志页面读取与清理"
```

### Task 3: 可靠统计和清理图片缓存

**Files:**
- Create: `lib/services/local_image_cache_service.dart`
- Create: `test/local_image_cache_service_test.dart`
- Modify: `lib/pages/about/about_page.dart`

- [ ] **Step 1: 写入缓存行为失败测试**

创建 `test/local_image_cache_service_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/local_image_cache_service.dart';

void main() {
  test('递归统计缓存并完整清理', () async {
    final root = await Directory.systemTemp.createTemp('image_cache_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final nested = Directory('${root.path}${Platform.pathSeparator}nested');
    await nested.create();
    await File('${root.path}${Platform.pathSeparator}a.bin')
        .writeAsBytes(List<int>.filled(3, 1));
    await File('${nested.path}${Platform.pathSeparator}b.bin')
        .writeAsBytes(List<int>.filled(5, 2));
    final service = LocalImageCacheService(directoryProvider: () async => root);

    expect(await service.sizeBytes(), 8);
    await service.clear();
    expect(await service.sizeBytes(), 0);
    expect(await root.exists(), isFalse);
  });

  test('缓存目录不存在时清理成功', () async {
    final parent = await Directory.systemTemp.createTemp('image_cache_none_');
    addTearDown(() => parent.delete(recursive: true));
    final missing = Directory('${parent.path}${Platform.pathSeparator}missing');
    final service = LocalImageCacheService(
      directoryProvider: () async => missing,
    );
    await service.clear();
    expect(await service.sizeBytes(), 0);
  });
}
```

- [ ] **Step 2: 运行测试并确认缺少实现**

```powershell
D:\flutter\bin\flutter.bat test test/local_image_cache_service_test.dart
```

预期：FAIL，找不到 `LocalImageCacheService`。

- [ ] **Step 3: 实现缓存服务**

创建 `lib/services/local_image_cache_service.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ImageCacheDirectoryProvider = Future<Directory> Function();

class LocalImageCacheService {
  LocalImageCacheService({ImageCacheDirectoryProvider? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final ImageCacheDirectoryProvider _directoryProvider;

  Future<int> sizeBytes() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) return 0;
    return _directorySize(directory);
  }

  Future<void> clear() async {
    final directory = await _directoryProvider();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<int> _directorySize(Directory directory) async {
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      } else if (entity is Directory) {
        total += await _directorySize(entity);
      }
    }
    return total;
  }

  static Future<Directory> _defaultDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(p.join(temporary.path, 'libCachedImageData'));
  }
}
```

- [ ] **Step 4: 让关于页面等待服务结果**

为 `AboutPage` 增加可注入服务并删除页面内目录递归及未使用字段：

```dart
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.cacheService});

  final LocalImageCacheService? cacheService;
}

late final LocalImageCacheService _cacheService;

@override
void initState() {
  super.initState();
  _cacheService = widget.cacheService ?? LocalImageCacheService();
  _getCacheSize();
}

Future<void> _getCacheSize() async {
  try {
    final totalSizeBytes = await _cacheService.sizeBytes();
    if (!mounted) return;
    setState(() => _cacheSizeMB = totalSizeBytes / (1024 * 1024));
  } on Object {
    if (!mounted) return;
    setState(() => _cacheSizeMB = 0);
  }
}
```

确认按钮替换为：

```dart
onPressed: () async {
  AppDialog.dismiss<void>();
  try {
    await _cacheService.clear();
    await _getCacheSize();
    AppDialog.showToast(message: '缓存已清理');
  } on Object {
    AppDialog.showToast(message: '清理缓存失败，请稍后重试');
  }
},
```

- [ ] **Step 5: 运行缓存和关于页面测试**

```powershell
D:\flutter\bin\flutter.bat test test/local_image_cache_service_test.dart test/about_page_content_test.dart
```

预期：PASS，0 failures。

- [ ] **Step 6: 提交**

```powershell
git add lib/services/local_image_cache_service.dart lib/pages/about/about_page.dart test/local_image_cache_service_test.dart
git commit -m "修复缓存统计与清理"
```

### Task 4: 第一批完整验证

**Files:**
- Verify only

- [ ] **Step 1: 格式检查**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
```

预期：0 changed，exit code 0。

- [ ] **Step 2: 完整测试**

```powershell
D:\flutter\bin\flutter.bat test
```

预期：All tests passed。

- [ ] **Step 3: 静态分析**

```powershell
D:\flutter\bin\flutter.bat analyze
```

预期：No issues found。

- [ ] **Step 4: 检查提交边界**

```powershell
git status --short
git log -4 --oneline
```

预期：仅保留用户原有 `.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md` 修改；第一批代码均已独立提交。
