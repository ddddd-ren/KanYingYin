import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_oauth_client.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';

void main() {
  test('授权地址使用 oob、basic netdisk 和当前 state', () {
    final client = BaiduOAuthClient(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      dio: Dio(),
    );

    final uri = client.buildAuthorizationUri(state: 'state-fixture');

    expect(uri.scheme, 'https');
    expect(uri.host, 'openapi.baidu.com');
    expect(uri.path, '/oauth/2.0/authorize');
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['client_id'], 'client-fixture');
    expect(uri.queryParameters['redirect_uri'], 'oob');
    expect(uri.queryParameters['scope'], 'basic,netdisk');
    expect(uri.queryParameters['state'], 'state-fixture');
  });

  test('授权码交换使用官方参数并计算 UTC 过期时间', () async {
    final now = DateTime.utc(2026, 7, 21, 10);
    final adapter = _QueueAdapter(<_FakeResponse>[
      _FakeResponse(200, await _fixture('token_success.json')),
    ]);
    final client = BaiduOAuthClient(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      dio: Dio()..httpClientAdapter = adapter,
      now: () => now,
    );

    final tokens = await client.exchangeCode('code-fixture');

    final request = adapter.requests.single;
    expect(request.uri.host, 'openapi.baidu.com');
    expect(request.uri.path, '/oauth/2.0/token');
    expect(request.queryParameters['grant_type'], 'authorization_code');
    expect(request.queryParameters['code'], 'code-fixture');
    expect(request.queryParameters['client_id'], 'client-fixture');
    expect(request.queryParameters['client_secret'], 'secret-fixture');
    expect(request.queryParameters['redirect_uri'], 'oob');
    expect(tokens.accessToken, 'access-fixture-new');
    expect(tokens.refreshToken, 'refresh-fixture-new');
    expect(tokens.scopes, containsAll(<String>{'basic', 'netdisk'}));
    expect(tokens.expiresAt, now.add(const Duration(days: 30)));
  });

  test('缺少 netdisk 权限时拒绝保存令牌', () async {
    final adapter = _QueueAdapter(const <_FakeResponse>[
      _FakeResponse(
        200,
        '{"access_token":"access-fixture","refresh_token":"refresh-fixture","expires_in":3600,"scope":"basic"}',
      ),
    ]);
    final client = BaiduOAuthClient(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(
      client.exchangeCode('code-fixture'),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        'type',
        CloudDriveErrorType.permission,
      )),
    );
  });

  test('并发刷新只请求一次并共同取得新令牌', () async {
    final adapter = _BlockingAdapter(await _fixture('token_success.json'));
    final client = BaiduOAuthClient(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    final first = client.refresh('refresh-fixture-old');
    final second = client.refresh('refresh-fixture-old');
    await adapter.started.future;
    adapter.release.complete();
    final tokens = await Future.wait(<Future<BaiduOAuthTokens>>[first, second]);

    expect(adapter.requests, hasLength(1));
    expect(
        adapter.requests.single.queryParameters['grant_type'], 'refresh_token');
    expect(adapter.requests.single.queryParameters['refresh_token'],
        'refresh-fixture-old');
    expect(tokens.map((value) => value.refreshToken).toSet(),
        <String>{'refresh-fixture-new'});
  });

  test('OAuth 错误分类不泄漏密钥、授权码和响应内容', () async {
    final adapter = _QueueAdapter(const <_FakeResponse>[
      _FakeResponse(
        400,
        '{"error":"invalid_grant","error_description":"code-fixture secret-fixture"}',
      ),
    ]);
    final client = BaiduOAuthClient(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    Object? captured;
    try {
      await client.exchangeCode('code-fixture');
    } catch (error) {
      captured = error;
    }

    expect(captured, isA<CloudDriveException>());
    expect(
      (captured! as CloudDriveException).type,
      CloudDriveErrorType.authentication,
    );
    expect(captured.toString(), isNot(contains('code-fixture')));
    expect(captured.toString(), isNot(contains('secret-fixture')));
    expect(captured.toString(), isNot(contains('invalid_grant')));
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

class _BlockingAdapter implements HttpClientAdapter {
  _BlockingAdapter(this.body);

  final String body;
  final List<RequestOptions> requests = <RequestOptions>[];
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    await release.future;
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
