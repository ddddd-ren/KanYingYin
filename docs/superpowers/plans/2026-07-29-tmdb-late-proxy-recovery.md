# TMDB 晚启动代理恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TMDB 请求在代理晚于应用启动时自动重新探测代理、重建网络客户端并重试一次。

**Architecture:** 恢复逻辑集中在 `TmdbClient`，以可注入的恢复回调和 Dio 工厂支持测试。只有连接类 Dio 异常触发恢复；成功后关闭旧 Dio、按最新设置创建新 Dio并重试一次，HTTP 响应错误与第二次失败不再重试。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Dio 5、Hive CE、flutter_test、Windows MSIX、SignTool

---

## 文件结构

- 修改 `lib/services/tmdb/tmdb_client.dart`：集中执行连接恢复、Dio 重建和一次性重试。
- 修改 `test/tmdb_client_test.dart`：覆盖网络失败恢复、恢复失败、HTTP 错误和第二次失败。
- 修改 `pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`UPDATE_DIALOG_COPY.md`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：发布 2.1.70。
- 修改 `test/identity_v2_zero_residue_test.dart`、`test/version_consistency_test.dart`、`test/version_history_current_test.dart`：同步版本和发布文案契约。

### Task 1: 建立失败的 TMDB 恢复测试

**Files:**
- Modify: `test/tmdb_client_test.dart`
- Test: `test/tmdb_client_test.dart`

- [x] **Step 1: 增加网络恢复测试和队列适配器**

在现有测试末尾加入：

```dart
  test('首次连接失败后恢复代理并使用新 Dio 重试一次', () async {
    final firstAdapter = _QueueAdapter([
      DioException(
        requestOptions: RequestOptions(path: '/search/movie'),
        type: DioExceptionType.connectionError,
      ),
    ]);
    final secondAdapter = _QueueAdapter([
      ResponseBody.fromString(
        '{"results":[{"id":1,"title":"Avatar"}]}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    ]);
    final firstDio = Dio()..httpClientAdapter = firstAdapter;
    final secondDio = Dio()..httpClientAdapter = secondAdapter;
    var recoveries = 0;
    var rebuilds = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: firstDio,
      recoverProxy: () async {
        recoveries += 1;
        return true;
      },
      dioFactory: () {
        rebuilds += 1;
        return secondDio;
      },
    );

    final results = await client.search('Avatar', TmdbMediaType.movie);

    expect(results.single.title, 'Avatar');
    expect(recoveries, 1);
    expect(rebuilds, 1);
    expect(firstAdapter.requestCount, 1);
    expect(secondAdapter.requestCount, 1);
  });

  test('代理恢复失败时保留首次网络异常且不重建 Dio', () async {
    final error = DioException(
      requestOptions: RequestOptions(path: '/search/movie'),
      type: DioExceptionType.connectionTimeout,
    );
    final adapter = _QueueAdapter([error]);
    final dio = Dio()..httpClientAdapter = adapter;
    var recoveries = 0;
    var rebuilds = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: dio,
      recoverProxy: () async {
        recoveries += 1;
        return false;
      },
      dioFactory: () {
        rebuilds += 1;
        return Dio();
      },
    );

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(same(error)),
    );
    expect(recoveries, 1);
    expect(rebuilds, 0);
    expect(adapter.requestCount, 1);
  });

  test('HTTP 响应错误不恢复代理', () async {
    final error = DioException.badResponse(
      statusCode: 401,
      requestOptions: RequestOptions(path: '/search/movie'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/search/movie'),
        statusCode: 401,
      ),
    );
    final adapter = _QueueAdapter([error]);
    final dio = Dio()..httpClientAdapter = adapter;
    var recoveries = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: dio,
      recoverProxy: () async {
        recoveries += 1;
        return true;
      },
      dioFactory: Dio.new,
    );

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(same(error)),
    );
    expect(recoveries, 0);
    expect(adapter.requestCount, 1);
  });

  test('重建后的请求失败时不进行第三次请求', () async {
    DioException failure(String path) => DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
    final firstAdapter = _QueueAdapter([failure('/first')]);
    final secondError = failure('/second');
    final secondAdapter = _QueueAdapter([secondError]);
    final firstDio = Dio()..httpClientAdapter = firstAdapter;
    final secondDio = Dio()..httpClientAdapter = secondAdapter;
    var recoveries = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: firstDio,
      recoverProxy: () async {
        recoveries += 1;
        return true;
      },
      dioFactory: () => secondDio,
    );

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(same(secondError)),
    );
    expect(recoveries, 1);
    expect(firstAdapter.requestCount, 1);
    expect(secondAdapter.requestCount, 1);
  });
```

在测试辅助类区域加入：

```dart
class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.outcomes);

  final List<Object> outcomes;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final outcome = outcomes[requestCount++];
    if (outcome is DioException) throw outcome;
    return outcome as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}
```

同时增加并发网络失败共享一次恢复和一次 Dio 重建的测试，使用 `Completer<bool>` 保持恢复任务挂起，直到两个旧 Dio 请求都进入失败路径。

- [x] **Step 2: 运行测试并确认红灯是构造参数不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_client_test.dart`

Expected: FAIL，`recoverProxy` 和 `dioFactory` 尚未定义。

### Task 2: 实现 TMDB 一次性代理恢复

**Files:**
- Modify: `lib/services/tmdb/tmdb_client.dart`
- Test: `test/tmdb_client_test.dart`

- [x] **Step 1: 增加可注入恢复依赖和可替换 Dio**

加入导入、类型和字段：

```dart
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';

typedef TmdbDioFactory = Dio Function();
typedef TmdbProxyRecovery = Future<bool> Function();

class TmdbClient implements ITmdbClient {
  final String apiKey;
  Dio _dio;
  final TmdbDioFactory? _dioFactory;
  final TmdbProxyRecovery? _recoverProxy;
  Future<bool>? _rebuildingDio;

  TmdbClient({
    required this.apiKey,
    Dio? dio,
    TmdbDioFactory? dioFactory,
    TmdbProxyRecovery? recoverProxy,
  })  : _dioFactory = dioFactory ?? (dio == null ? _createDefaultDio : null),
        _recoverProxy = recoverProxy ??
            (dio == null ? ProxyManager.recoverOnlineResourceProxy : null),
        _dio = dio ?? (dioFactory ?? _createDefaultDio)();
```

- [x] **Step 2: 增加网络错误判定和一次性执行器**

在 `TmdbClient` 内加入：

```dart
  Future<T> _withProxyRecovery<T>(
    Future<T> Function(Dio dio) request,
  ) async {
    try {
      return await request(_dio);
    } on DioException catch (error, stackTrace) {
      final recoverProxy = _recoverProxy;
      final dioFactory = _dioFactory;
      if (!_isRecoverableNetworkError(error) ||
          recoverProxy == null ||
          dioFactory == null) {
        rethrow;
      }

      bool recovered;
      try {
        recovered = await recoverProxy();
      } catch (recoveryError, recoveryStackTrace) {
        AppLogger().w(
          'TMDB: 代理恢复失败',
          error: recoveryError,
          stackTrace: recoveryStackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (!recovered) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      final previousDio = _dio;
      _dio = dioFactory();
      previousDio.close(force: true);
      return request(_dio);
    }
  }

  bool _isRecoverableNetworkError(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError;
  }
```

- [x] **Step 3: 让搜索与详情请求统一经过执行器**

搜索请求改为：

```dart
    final response = await _withProxyRecovery(
      (dio) => dio.get<Map<String, dynamic>>(
        '/search/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}',
        queryParameters: {
          ..._authenticationQuery,
          'query': query,
          'language': language,
          'include_adult': false,
        },
        options: _authenticationOptions,
      ),
    );
```

详情请求改为：

```dart
    final response = await _withProxyRecovery(
      (dio) => dio.get<Map<String, dynamic>>(
        '/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}/$id',
        queryParameters: {..._authenticationQuery, 'language': language},
        options: _authenticationOptions,
      ),
    );
```

- [x] **Step 4: 运行测试并确认绿灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_client_test.dart test/network_infrastructure_test.dart`

Expected: PASS；TMDB 恢复测试和 TLS/代理基础设施契约全部通过。

- [x] **Step 5: 格式化并提交核心修复**

```powershell
D:\flutter\bin\dart.bat format lib/services/tmdb/tmdb_client.dart test/tmdb_client_test.dart
git add -- lib/services/tmdb/tmdb_client.dart test/tmdb_client_test.dart
git diff --cached --check
git commit -m "修复 TMDB 晚启动代理恢复"
```

### Task 3: 发布 2.1.70

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [x] **Step 1: 查询并记录当前 Windows 已安装版本**

Run: `Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,InstallLocation`

Expected: 明确记录已安装版本；未安装时输出“未安装”。

- [x] **Step 2: 同步版本号为 2.1.70**

```yaml
version: 2.1.70+20170
```

```yaml
  msix_version: 2.1.70.0
```

将 `AppVersion.current`、README 当前版本和两个版本契约测试同步为 `2.1.70`、构建号同步为 `20170`。

- [x] **Step 3: 更新发布文案**

在 `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 和 `version_history.dart` 使用一致文案：

```text
修复看影音早于代理软件启动时，TMDB 搜索一直提示网络失败的问题
TMDB 遇到连接失败后会重新探测本机代理，按最新设置重建网络客户端并自动重试一次
API Key 错误、服务器响应错误和限流不会重复请求；本地媒体库扫描与播放器不依赖 TMDB
本次修复不会修改或删除本地及网盘媒体库中的原始视频、字幕或其他文件
```

在 `test/version_history_current_test.dart` 增加 2.1.70 对应断言，并把 `test/version_consistency_test.dart` 的当前版本关键词更新为“代理”“重试”“API Key”“播放器”“不会修改或删除”。

- [x] **Step 4: 运行版本契约测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart test/release_config_contract_test.dart`

Expected: PASS，版本号与发布文案一致。

### Task 4: 完整验证与 Windows 交付

**Files:**
- Generate: `build/windows/x64/runner/Release/kanyingyin.exe`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.70.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.70-异机安装包.zip`

- [x] **Step 1: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部测试通过，0 failures。

- [x] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`

- [x] **Step 3: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: Exit code 0，生成本轮 `kanyingyin.exe` 和 `data/app.so`。

- [x] **Step 4: 使用签名脚本生成并验证 MSIX**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/windows/build_signed_release.ps1`

Expected: SignTool 0 warning、0 error；桌面生成 2.1.70 的 MSIX 和异机安装 ZIP。

- [x] **Step 5: 核对清单版本和桌面产物**

读取 MSIX 中 `AppxManifest.xml`，确认 Identity 为 `com.kanyingyin.player`、Version 为 `2.1.70.0`、架构为 `x64`。确认桌面 MSIX 与构建产物 SHA-256一致。

- [x] **Step 6: 检查差异并提交发布改动**

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml lib/core/app_version.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git add -- pubspec.yaml lib/core/app_version.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart docs/superpowers/plans/2026-07-29-tmdb-late-proxy-recovery.md
git diff --cached --check
git commit -m "发布 TMDB 代理恢复修复"
```

- [x] **Step 7: 最终状态核对**

Run: `git status --short --branch`

Expected: 工作区干净，当前分支保留迅雷网盘原有提交并新增本轮 TMDB 修复提交。
