import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';

void main() {
  test('账号验证发送 Cookie、User-Agent 和受限超时', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"status":200,"code":0,"data":{"nickname":"account_fixture"}}',
      ),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = QuarkApiClient(
      cookie: 'session=cookie-fixture',
      dio: dio,
    );

    final account = await client.getAccount();

    final request = adapter.requests.single;
    expect(account.nickname, 'account_fixture');
    expect(request.uri.host, 'pan.quark.cn');
    expect(request.headers['Cookie'], 'session=cookie-fixture');
    expect(request.headers['User-Agent'], contains('Windows NT 10.0'));
    expect(request.connectTimeout, const Duration(seconds: 10));
    expect(request.sendTimeout, const Duration(seconds: 15));
    expect(request.receiveTimeout, const Duration(seconds: 30));
    await client.close();
  });

  test('429 有上限重试，401 不重试', () async {
    final delays = <Duration>[];
    final rateLimitedAdapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(429, '{"status":429,"code":429,"message":"频繁"}'),
      const _FakeResponse(
        200,
        '{"status":200,"code":0,"data":{"nickname":"account_fixture"}}',
      ),
    ]);
    final rateLimited = QuarkApiClient(
      cookie: 'session=cookie-fixture',
      dio: Dio()..httpClientAdapter = rateLimitedAdapter,
      delay: (duration) async => delays.add(duration),
    );

    await rateLimited.getAccount();

    expect(rateLimitedAdapter.requests, hasLength(2));
    expect(delays, const <Duration>[Duration(milliseconds: 500)]);

    final authAdapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(401, '{"status":401,"code":41001}'),
    ]);
    final authClient = QuarkApiClient(
      cookie: 'session=cookie-fixture',
      dio: Dio()..httpClientAdapter = authAdapter,
    );

    await expectLater(
      authClient.getAccount(),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.authentication)),
    );
    expect(authAdapter.requests, hasLength(1));
  });
}

class _FakeResponse {
  const _FakeResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

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
