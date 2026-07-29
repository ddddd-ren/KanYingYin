# TMDB 官方备用端点 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 当 `api.themoviedb.org` 在当前网络不可达时，自动切换到可直连的 TMDB 官方备用端点 `api.tmdb.org`，同时保留代理晚启动恢复能力。

**Architecture:** 新建一个只负责 TMDB 官方端点和可重试错误判定的策略类，供 `TmdbClient`、旧海报搜索服务和代理探测共用。`TmdbClient` 先尝试当前首选端点，主端点发生连接或 5xx 故障时尝试备用端点；两个端点都失败后才执行现有代理恢复并重建 Dio。成功的备用端点在当前客户端运行期保持首选。

**Tech Stack:** Flutter 3.41.9、Dart、Dio、flutter_test、PowerShell

---

### Task 1: 定义唯一的 TMDB 官方端点策略

**Files:**
- Create: `lib/services/tmdb/tmdb_endpoint_policy.dart`
- Create: `test/tmdb_endpoint_policy_test.dart`

- [ ] **Step 1: 写入失败测试，固定官方域名和故障边界**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_endpoint_policy.dart';

void main() {
  test('只暴露 TMDB 官方 API 主端点和备用端点', () {
    expect(TmdbEndpointPolicy.apiBaseUrls, <String>[
      'https://api.themoviedb.org/3',
      'https://api.tmdb.org/3',
    ]);
    expect(
      TmdbEndpointPolicy.configurationUris.map((uri) => uri.host),
      <String>['api.themoviedb.org', 'api.tmdb.org'],
    );
  });

  test('连接错误和 5xx 可以切换而 401 不切换', () {
    final options = RequestOptions(path: '/configuration');
    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ),
      isTrue,
    );
    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException.badResponse(
          statusCode: 503,
          requestOptions: options,
          response: Response<void>(requestOptions: options, statusCode: 503),
        ),
      ),
      isTrue,
    );
    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException.badResponse(
          statusCode: 401,
          requestOptions: options,
          response: Response<void>(requestOptions: options, statusCode: 401),
        ),
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: 运行测试并确认因策略类不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_endpoint_policy_test.dart`

Expected: FAIL，提示找不到 `tmdb_endpoint_policy.dart` 或 `TmdbEndpointPolicy`。

- [ ] **Step 3: 实现端点和错误判定策略**

```dart
import 'package:dio/dio.dart';

class TmdbEndpointPolicy {
  const TmdbEndpointPolicy._();

  static const String primaryApiBaseUrl =
      'https://api.themoviedb.org/3';
  static const String fallbackApiBaseUrl = 'https://api.tmdb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w780';
  static const List<String> apiBaseUrls = <String>[
    primaryApiBaseUrl,
    fallbackApiBaseUrl,
  ];

  static final List<Uri> configurationUris = List<Uri>.unmodifiable(
    apiBaseUrls.map((baseUrl) => Uri.parse('$baseUrl/configuration')),
  );

  static bool canTryAnotherEndpoint(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }
    final statusCode = error.response?.statusCode;
    return error.type == DioExceptionType.badResponse &&
        statusCode != null &&
        statusCode >= 500 &&
        statusCode < 600;
  }
}
```

- [ ] **Step 4: 运行策略测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_endpoint_policy_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交端点策略**

```powershell
git add -- lib/services/tmdb/tmdb_endpoint_policy.dart test/tmdb_endpoint_policy_test.dart
git commit -m "新增 TMDB 官方备用端点策略"
```

### Task 2: 在 TmdbClient 中实现运行期故障转移

**Files:**
- Modify: `lib/services/tmdb/tmdb_client.dart`
- Modify: `test/tmdb_client_test.dart`

- [ ] **Step 1: 增加主站失败、备用保持和 401 不切换测试**

在 `test/tmdb_client_test.dart` 增加能按 `options.uri.host` 返回结果的适配器，并写入以下断言：

```dart
test('主端点连接失败后使用官方备用端点并在运行期保持', () async {
  final adapter = _HostAdapter((options, hostCount) {
    if (options.uri.host == 'api.themoviedb.org') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      '{"results":[{"id":1,"title":"Avatar"}]}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  });
  final dio = Dio()..httpClientAdapter = adapter;
  final client = TmdbClient(
    apiKey: 'key',
    dio: dio,
    recoverProxy: () async => false,
    dioFactory: () => dio,
  );

  await client.search('Avatar', TmdbMediaType.movie);
  await client.search('Avatar 2', TmdbMediaType.movie);

  expect(adapter.hosts, <String>[
    'api.themoviedb.org',
    'api.tmdb.org',
    'api.tmdb.org',
  ]);
});

test('主端点 401 时不向备用端点重复发送 API Key', () async {
  final adapter = _HostAdapter((options, hostCount) {
    return ResponseBody.fromString('{"status_code":7}', 401);
  });
  final dio = Dio()..httpClientAdapter = adapter;
  final client = TmdbClient(apiKey: 'bad-key', dio: dio);

  await expectLater(
    client.search('Avatar', TmdbMediaType.movie),
    throwsA(isA<DioException>()),
  );
  expect(adapter.hosts, <String>['api.themoviedb.org']);
});
```

`_HostAdapter` 的完整测试实现：

```dart
typedef _HostResponder = Object Function(
  RequestOptions options,
  int hostRequestCount,
);

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.responder);

  final _HostResponder responder;
  final List<String> hosts = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hosts.add(options.uri.host);
    final outcome = responder(
      options,
      hosts.where((host) => host == options.uri.host).length,
    );
    if (outcome is DioException) throw outcome;
    return outcome as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: 运行客户端测试并确认新测试失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_client_test.dart`

Expected: FAIL；当前客户端只访问主端点。

- [ ] **Step 3: 改用绝对官方端点并实现“备用优先、代理兜底”**

在 `TmdbClient` 中导入策略类，增加：

```dart
String _preferredBaseUrl = TmdbEndpointPolicy.primaryApiBaseUrl;
```

把 `search` 和 `_detailsForLanguage` 的回调改成接收 `baseUrl` 并请求绝对地址：

```dart
final response = await _withEndpointRecovery(
  (dio, baseUrl) => dio.get<Map<String, dynamic>>(
    '$baseUrl/search/${mediaType == TmdbMediaType.movie ? 'movie' : 'tv'}',
    queryParameters: <String, dynamic>{
      ..._authenticationQuery,
      'query': query,
      'language': language,
      'include_adult': false,
    },
    options: _authenticationOptions,
  ),
);
```

用以下方法替换 `_withProxyRecovery`；保留现有 `_recoverAndRebuild` 的并发合并，并在 Dio 重建后把首选端点重置为主端点：

```dart
Future<T> _withEndpointRecovery<T>(
  Future<T> Function(Dio dio, String baseUrl) request,
) async {
  final firstBaseUrl = _preferredBaseUrl;
  try {
    return await request(_dio, firstBaseUrl);
  } on DioException catch (firstError) {
    if (!TmdbEndpointPolicy.canTryAnotherEndpoint(firstError)) rethrow;

    final secondBaseUrl =
        firstBaseUrl == TmdbEndpointPolicy.primaryApiBaseUrl
            ? TmdbEndpointPolicy.fallbackApiBaseUrl
            : TmdbEndpointPolicy.primaryApiBaseUrl;
    try {
      final result = await request(_dio, secondBaseUrl);
      _preferredBaseUrl = secondBaseUrl;
      AppLogger().i(
        'TMDB: 已切换官方端点 ${Uri.parse(secondBaseUrl).host}',
      );
      return result;
    } on DioException catch (secondError, secondStackTrace) {
      if (!TmdbEndpointPolicy.canTryAnotherEndpoint(secondError)) rethrow;
      final recoverProxy = _recoverProxy;
      final dioFactory = _dioFactory;
      if (recoverProxy == null || dioFactory == null) {
        Error.throwWithStackTrace(secondError, secondStackTrace);
      }
      final recovered = await _recoverAndRebuild(recoverProxy, dioFactory);
      if (!recovered) {
        Error.throwWithStackTrace(secondError, secondStackTrace);
      }
      _preferredBaseUrl = TmdbEndpointPolicy.primaryApiBaseUrl;
      return request(_dio, _preferredBaseUrl);
    }
  }
}
```

删除不再使用的 `_isRecoverableNetworkError`。默认 Dio 的 `baseUrl` 使用 `TmdbEndpointPolicy.primaryApiBaseUrl`，但业务请求始终传绝对 URL。

- [ ] **Step 4: 调整既有代理恢复测试的请求队列**

把“首次连接失败后恢复代理”场景改为：旧 Dio 对主、备用端点各失败一次；`recoverProxy` 成功后新 Dio 对主端点成功。保留以下断言：

```dart
final firstAdapter = _QueueAdapter(<Object>[
  failure('/primary'),
  failure('/fallback'),
]);
final secondAdapter = _QueueAdapter(<Object>[
  ResponseBody.fromString(
    '{"results":[{"id":1,"title":"Avatar"}]}',
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
    },
  ),
]);

expect(recoveries, 1);
expect(rebuilds, 1);
expect(firstAdapter.requestCount, 2);
expect(secondAdapter.requestCount, 1);
```

并发恢复场景使用四个旧 Dio 失败结果和两个新 Dio 成功结果：

```dart
final firstAdapter = _QueueAdapter(<Object>[
  failure('/request-1-primary'),
  failure('/request-2-primary'),
  failure('/request-1-fallback'),
  failure('/request-2-fallback'),
]);
final secondAdapter = _QueueAdapter(<Object>[
  success(1),
  success(2),
]);
// 释放 recoveryGate 后：
expect(recoveries, 1);
expect(rebuilds, 1);
expect(firstAdapter.requestCount, 4);
expect(secondAdapter.requestCount, 2);
```

- [ ] **Step 5: 运行客户端和策略测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_endpoint_policy_test.dart test/tmdb_client_test.dart`

Expected: PASS；401 测试只有一个主端点请求，连接失败测试会保持备用端点。

- [ ] **Step 6: 提交客户端故障转移**

```powershell
git add -- lib/services/tmdb/tmdb_client.dart test/tmdb_client_test.dart
git commit -m "修复 TMDB 无代理网络访问"
```

### Task 3: 统一旧海报搜索和代理探测端点

**Files:**
- Modify: `lib/services/poster_service.dart`
- Modify: `test/poster_service_download_test.dart`
- Modify: `lib/utils/proxy_manager.dart`

- [ ] **Step 1: 把旧海报服务测试改为只允许两个官方域名**

将现有测试名称改为“TMDB 主站失败时只尝试官方备用域名”，断言改为：

```dart
expect(hosts, <String>[
  'api.themoviedb.org',
  'api.tmdb.org',
]);
expect(
  hosts,
  everyElement(
    isIn(<String>['api.themoviedb.org', 'api.tmdb.org']),
  ),
);
```

- [ ] **Step 2: 运行海报测试并确认只访问主站导致失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/poster_service_download_test.dart`

Expected: FAIL；实际主机列表缺少 `api.tmdb.org`。

- [ ] **Step 3: 让 PosterService 复用端点策略**

删除 `_baseUrl` 和重复的 `_imageBaseUrl`，用 `TmdbEndpointPolicy.imageBaseUrl` 构造海报 URL。将 `_ensureBaseUrl` 改为：

```dart
Future<String?> _ensureBaseUrl(String apiKey) async {
  if (_workingBaseUrl != null) return _workingBaseUrl;

  for (final baseUrl in TmdbEndpointPolicy.apiBaseUrls) {
    try {
      await _dio.get<Object?>(
        '$baseUrl/configuration',
        queryParameters: <String, String>{'api_key': apiKey},
      );
      _workingBaseUrl = baseUrl;
      return baseUrl;
    } on DioException catch (error) {
      if (!TmdbEndpointPolicy.canTryAnotherEndpoint(error)) return null;
    }
  }
  return null;
}
```

- [ ] **Step 4: 让 ProxyManager 把两个官方配置地址视为同一可达组**

```dart
_ProxyProbeGroup(
  name: 'TMDB API',
  uris: TmdbEndpointPolicy.configurationUris,
),
```

这表示主站或备用站任一可直连即可继续，不会因为主站在中国网络超时而强制要求 VPN。

- [ ] **Step 5: 运行相关测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/poster_service_download_test.dart test/tmdb_client_test.dart test/network_infrastructure_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交旧入口统一修改**

```powershell
git add -- lib/services/poster_service.dart test/poster_service_download_test.dart lib/utils/proxy_manager.dart
git commit -m "统一 TMDB 官方端点探测"
```

### Task 4: 验证 TMDB 子计划

**Files:**
- Verify only

- [ ] **Step 1: 运行全部 TMDB 与海报相关测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/tmdb_endpoint_policy_test.dart test/tmdb_client_test.dart test/tmdb_scrape_policy_test.dart test/poster_service_download_test.dart`

Expected: PASS，0 failures。

- [ ] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 3: 检查本子计划差异**

```powershell
git status --short
git diff --check
git log -4 --oneline
```

Expected: 没有未提交的 TMDB 端点代码；最近提交只包含本计划列出的文件。
