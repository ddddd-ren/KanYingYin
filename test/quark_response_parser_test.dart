import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_response_parser.dart';

void main() {
  final parser = QuarkResponseParser();

  test('解析脱敏账号、目录和播放夹具', () async {
    final account = parser.parseAccount(await _fixture('account_success.json'));
    final page =
        parser.parseDirectoryPage(await _fixture('directory_page_1.json'));
    final playback = parser.parsePlayback(
      await _fixture('playback_success.json'),
      fileId: 'fid_fixture_video',
    );

    expect(account.nickname, 'account_fixture');
    expect(page.items, hasLength(3));
    expect(page.items.first.id, 'fid_fixture_directory');
    expect(page.items.first.isDirectory, isTrue);
    expect(page.page, 1);
    expect(page.total, 3);
    expect(playback.fileId, 'fid_fixture_video');
    expect(playback.uri.host, 'media.quark-fixture.invalid');
    expect(playback.uri.path, '/4k');
  });

  test('关键结构缺失时明确映射为接口不兼容', () {
    expect(
      () => parser.parseDirectoryPage(<String, Object?>{
        'status': 200,
        'code': 0,
        'data': <String, Object?>{},
      }),
      throwsA(
        isA<CloudDriveException>()
            .having(
                (error) => error.type, 'type', CloudDriveErrorType.incompatible)
            .having((error) => error.message, 'message', '当前版本暂不兼容夸克接口'),
      ),
    );
  });

  test('业务错误区分 Cookie、限流和不存在', () {
    expect(
      () => parser.ensureSuccess(<String, Object?>{
        'status': 401,
        'code': 41001,
        'message': '登录失效',
      }),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.authentication)),
    );
    expect(
      () => parser.ensureSuccess(<String, Object?>{
        'status': 429,
        'code': 429,
        'message': '请求过于频繁',
      }),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.rateLimited)),
    );
    expect(
      () => parser.ensureSuccess(<String, Object?>{
        'status': 404,
        'code': 404,
        'message': '文件不存在',
      }),
      throwsA(isA<CloudDriveException>()
          .having((error) => error.type, 'type', CloudDriveErrorType.notFound)),
    );
  });

  test('播放响应优先选择最高可用清晰度', () {
    final playback = parser.parsePlayback(<String, Object?>{
      'status': 200,
      'code': 0,
      'data': <String, Object?>{
        'fid': 'fid_fixture_video',
        'video_list': <Object?>[
          <String, Object?>{
            'resolution': 'super',
            'video_info': <String, Object?>{
              'url': 'https://media.quark-fixture.invalid/super',
            },
          },
          <String, Object?>{
            'resolution': '4k',
            'video_info': <String, Object?>{
              'url': 'https://media.quark-fixture.invalid/4k',
            },
          },
          <String, Object?>{
            'resolution': '2k',
            'video_info': <String, Object?>{'url': ''},
          },
        ],
      },
    }, fileId: 'fid_fixture_video');

    expect(playback.uri.path, '/4k');
  });

  test('播放响应没有可用地址时明确报接口不兼容', () {
    expect(
      () => parser.parsePlayback(<String, Object?>{
        'status': 200,
        'code': 0,
        'data': <String, Object?>{
          'video_list': <Object?>[
            <String, Object?>{
              'resolution': '4k',
              'video_info': <String, Object?>{'url': ''},
            },
          ],
        },
      }, fileId: 'fid_fixture_video'),
      throwsA(isA<CloudDriveException>().having(
          (error) => error.type, 'type', CloudDriveErrorType.incompatible)),
    );
  });
}

Future<Object?> _fixture(String name) async {
  final text =
      await File('test/fixtures/quark/$name').readAsString(encoding: utf8);
  return jsonDecode(text);
}
