import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_api_client.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('账号请求使用官方 uinfo 接口和 Access Token', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      _FakeResponse(200, await _fixture('account_success.json')),
    ]);
    final client = BaiduApiClient(
      accessToken: 'access-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    final account = await client.account();

    final request = adapter.requests.single;
    expect(account.displayName, 'account_fixture');
    expect(request.uri.host, 'pan.baidu.com');
    expect(request.uri.path, '/rest/2.0/xpan/nas');
    expect(request.queryParameters['method'], 'uinfo');
    expect(request.queryParameters['access_token'], 'access-fixture');
  });

  test('目录按 start 分页并按 fs_id 去重', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      _FakeResponse(200, await _fixture('directory_page_1.json')),
      _FakeResponse(200, await _fixture('directory_empty.json')),
    ]);
    final client = BaiduApiClient(
      accessToken: 'access-fixture',
      dio: Dio()..httpClientAdapter = adapter,
      pageSize: 2,
    );

    final entries = await client.listDirectory(
      const CloudRemoteRef(id: '0', path: '/影视'),
    );

    expect(entries.map((entry) => entry.fsId), <String>['1001', '1002']);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.queryParameters['method'], 'list');
    expect(adapter.requests.first.queryParameters['dir'], '/影视');
    expect(adapter.requests.first.queryParameters['start'], 0);
    expect(adapter.requests.first.queryParameters['limit'], 2);
    expect(adapter.requests.last.queryParameters['start'], 2);
  });

  test('重复目录页在第三次请求前报告不兼容', () async {
    final page = await _fixture('directory_page_1.json');
    final adapter = _QueueAdapter(<_FakeResponse>[
      _FakeResponse(200, page),
      _FakeResponse(200, page),
    ]);
    final client = BaiduApiClient(
      accessToken: 'access-fixture',
      dio: Dio()..httpClientAdapter = adapter,
      pageSize: 2,
    );

    await expectLater(
      client.listDirectory(const CloudRemoteRef(id: '0', path: '/影视')),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        'type',
        CloudDriveErrorType.incompatible,
      )),
    );
    expect(adapter.requests, hasLength(2));
  });

  test('文件详情请求使用 fsids JSON 和 dlink=1', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      _FakeResponse(200, await _fixture('filemetas_success.json')),
    ]);
    final client = BaiduApiClient(
      accessToken: 'access-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    final details = await client.fileDetails(
      const CloudRemoteRef(id: '1002', path: '/影视/示例电影.mkv'),
      includeDownloadLink: true,
    );

    final request = adapter.requests.single;
    expect(details.fsId, '1002');
    expect(request.uri.path, '/rest/2.0/xpan/multimedia');
    expect(request.queryParameters['method'], 'filemetas');
    expect(request.queryParameters['fsids'], '[1002]');
    expect(request.queryParameters['dlink'], 1);
  });

  test('HTTP 429 按 500ms 退避后重试成功', () async {
    final delays = <Duration>[];
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(429, '{"errno":31034}'),
      _FakeResponse(200, await _fixture('account_success.json')),
    ]);
    final client = BaiduApiClient(
      accessToken: 'access-fixture',
      dio: Dio()..httpClientAdapter = adapter,
      delay: (duration) async => delays.add(duration),
    );

    final account = await client.account();

    expect(account.displayName, 'account_fixture');
    expect(adapter.requests, hasLength(2));
    expect(delays, const <Duration>[Duration(milliseconds: 500)]);
  });

  test('HTTP 429 转换为限流且异常不泄漏 Access Token', () async {
    final adapter = _QueueAdapter(const <_FakeResponse>[
      _FakeResponse(429, '{"errno":31034,"access_token":"access-fixture"}'),
    ]);
    final client = BaiduApiClient(
      accessToken: 'access-fixture',
      dio: Dio()..httpClientAdapter = adapter,
      maxRateLimitRetries: 0,
    );

    Object? captured;
    try {
      await client.account();
    } catch (error) {
      captured = error;
    }

    expect(captured, isA<CloudDriveException>());
    expect((captured! as CloudDriveException).type,
        CloudDriveErrorType.rateLimited);
    expect(captured.toString(), isNot(contains('access-fixture')));
  });
}

Future<String> _fixture(String name) =>
    File('test/fixtures/baidu/$name').readAsString();

class _FakeResponse {
  const _FakeResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(List<_FakeResponse> responses)
      : responses = List<_FakeResponse>.of(responses);

  final List<_FakeResponse> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = responses.removeAt(0);
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
