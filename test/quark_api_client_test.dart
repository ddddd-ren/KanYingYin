import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';

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

  test('播放使用夸克项目播放接口并请求全部清晰度', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"status":200,"code":0,"data":{"video_list":[{"resolution":"4k","video_info":{"url":"https://media.quark-fixture.invalid/4k"}}]}}',
      ),
    ]);
    final client = QuarkApiClient(
      cookie: 'session=cookie-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    final playback = await client.resolvePlayback('fid_fixture_video');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/1/clouddrive/file/v2/play/project');
    expect(request.uri.queryParameters, <String, String>{
      'pr': 'ucpro',
      'fr': 'pc',
    });
    expect(request.data, <String, Object?>{
      'fid': 'fid_fixture_video',
      'resolutions': 'low,normal,high,super,2k,4k',
      'supports': 'fmp4_av,m3u8,dolby_vision',
    });
    expect(request.headers['Cookie'], 'session=cookie-fixture');
    expect(request.headers['Referer'], 'https://pan.quark.cn');
    expect(playback.fileId, 'fid_fixture_video');
    expect(playback.uri.path, '/4k');
    await client.close();
  });

  test('项目播放没有转码地址时回退原文件下载接口', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"status":200,"code":0,"data":{"video_list":[]}}',
      ),
      const _FakeResponse(
        200,
        '{"status":200,"code":0,"data":[{"download_url":"https://download.drive.quark.cn/original"}]}',
      ),
    ]);
    final client = QuarkApiClient(
      cookie: 'session=cookie-fixture',
      dio: Dio()..httpClientAdapter = adapter,
    );

    final playback = await client.resolvePlayback('fid_fixture_video');

    expect(adapter.requests, hasLength(2));
    expect(
      adapter.requests.first.uri.path,
      '/1/clouddrive/file/v2/play/project',
    );
    expect(adapter.requests.last.uri.path, '/1/clouddrive/file/download');
    expect(adapter.requests.last.data, <String, Object?>{
      'fids': <String>['fid_fixture_video'],
    });
    expect(playback.uri.path, '/original');
    expect(playback.type, QuarkPlaybackLinkType.originalDownload);
    await client.close();
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
