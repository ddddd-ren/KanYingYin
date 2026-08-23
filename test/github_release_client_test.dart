import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/app_update/data/github_release_client.dart';

void main() {
  test('请求官方仓库并选择语义版本最高的正式 Release', () async {
    final adapter = _JsonAdapter(<Object?>[
      _releaseJson(tag: 'v2.1.169', draft: true),
      _releaseJson(tag: 'v2.1.170', prerelease: true),
      _releaseJson(tag: 'invalid'),
      _releaseJson(tag: 'v2.10.0'),
      _releaseJson(tag: 'v2.9.99'),
    ]);
    final client = GitHubReleaseClient(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final release = await client.fetchLatestStableRelease();

    expect(release.version.toString(), '2.10.0');
    expect(adapter.request.uri.host, 'api.github.com');
    expect(
      adapter.request.uri.path,
      '/repos/ddddd-ren/KanYingYin/releases',
    );
    expect(adapter.request.uri.queryParameters['per_page'], '30');
  });

  test('解析资产大小、下载地址和 GitHub SHA-256 摘要', () async {
    final client = GitHubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = _JsonAdapter(<Object?>[
          _releaseJson(
            tag: 'v2.1.168',
            digest:
                'sha256:ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD',
          ),
        ]),
    );

    final asset = (await client.fetchLatestStableRelease()).windowsInstaller;

    expect(asset.size, 123456);
    expect(
      asset.sha256,
      'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd',
    );
    expect(asset.downloadUri.scheme, 'https');
  });

  test('最高正式版缺少合法摘要时明确失败', () async {
    final client = GitHubReleaseClient(
      dio: Dio()
        ..httpClientAdapter = _JsonAdapter(<Object?>[
          _releaseJson(tag: 'v2.1.168', digest: null),
        ]),
    );

    await expectLater(
      client.fetchLatestStableRelease(),
      throwsA(isA<FormatException>()),
    );
  });

  test('最高正式版存在多个版本匹配的 EXE 时明确失败', () async {
    final value = _releaseJson(tag: 'v2.1.168');
    final assets = value['assets']! as List<Object?>;
    assets.add(<String, Object?>{
      'name': 'KanYingYin-2.1.168.exe',
      'size': 123456,
      'digest':
          'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'browser_download_url': 'https://example.invalid/second.exe',
    });
    final client = GitHubReleaseClient(
      dio: Dio()..httpClientAdapter = _JsonAdapter(<Object?>[value]),
    );

    await expectLater(
      client.fetchLatestStableRelease(),
      throwsA(isA<StateError>()),
    );
  });
}

Map<String, Object?> _releaseJson({
  required String tag,
  bool draft = false,
  bool prerelease = false,
  String? digest =
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) {
  final version = tag.startsWith('v') ? tag.substring(1) : 'invalid';
  return <String, Object?>{
    'tag_name': tag,
    'name': '看影音 $version',
    'body': '更新说明',
    'draft': draft,
    'prerelease': prerelease,
    'published_at': '2026-08-23T08:00:00Z',
    'assets': <Object?>[
      <String, Object?>{
        'name': '看影音-$version-测试版-安装程序.exe',
        'size': 123456,
        'digest': digest,
        'browser_download_url': 'https://example.invalid/$version.exe',
      },
    ],
  };
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.value);

  final Object? value;
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
