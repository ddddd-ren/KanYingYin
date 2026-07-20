import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_response_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';

void main() {
  const parser = BaiduResponseParser();

  test('账号响应解析脱敏昵称、用户标识和会员类型', () async {
    final account = parser.parseAccount(await _fixture('account_success.json'));

    expect(account.displayName, 'account_fixture');
    expect(account.userId, '123456789');
    expect(account.vipType, 2);
  });

  test('目录响应保留 fs_id、路径、大小、时间和目录类型', () async {
    final page =
        parser.parseDirectoryPage(await _fixture('directory_page_1.json'));

    expect(page.entries, hasLength(2));
    expect(page.entries.first.fsId, '1001');
    expect(page.entries.first.path, '/影视/示例剧');
    expect(page.entries.first.isDirectory, isTrue);
    expect(page.entries.last.fsId, '1002');
    expect(page.entries.last.size, 4294967296);
    expect(page.entries.last.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000100 * 1000, isUtc: true));
  });

  test('文件详情解析 dlink 并拒绝请求外的 fs_id', () async {
    final details = parser.parseFileDetails(
      await _fixture('filemetas_success.json'),
      expectedFsId: '1002',
    );

    expect(details.fsId, '1002');
    expect(details.name, '示例电影.mkv');
    expect(details.downloadUri?.scheme, 'https');
    expect(details.downloadUri?.host, 'download.baidu-fixture.invalid');

    expect(
      () => parser.parseFileDetails(
        <String, Object?>{
          'errno': 0,
          'list': <Object?>[
            <String, Object?>{
              'fs_id': 9999,
              'path': '/other.mkv',
              'server_filename': 'other.mkv',
              'size': 4,
              'isdir': 0,
              'server_mtime': 1,
            },
          ],
        },
        expectedFsId: '1002',
      ),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        'type',
        CloudDriveErrorType.incompatible,
      )),
    );
  });

  test('文件详情兼容旧 server_filename 字段', () {
    final details = parser.parseFileDetails(
      <String, Object?>{
        'errno': 0,
        'list': <Object?>[
          <String, Object?>{
            'fs_id': 1002,
            'path': '/影视/旧响应.mkv',
            'server_filename': '旧响应.mkv',
            'size': 8,
            'isdir': 0,
            'server_mtime': 1700000100,
            'dlink': 'https://download.baidu-fixture.invalid/legacy',
          },
        ],
      },
      expectedFsId: '1002',
    );

    expect(details.name, '旧响应.mkv');
  });

  test('文件详情缺少两个文件名字段时拒绝响应', () {
    expect(
      () => parser.parseFileDetails(
        <String, Object?>{
          'errno': 0,
          'list': <Object?>[
            <String, Object?>{
              'fs_id': 1002,
              'path': '/影视/无文件名.mkv',
              'size': 8,
              'isdir': 0,
              'server_mtime': 1700000100,
            },
          ],
        },
        expectedFsId: '1002',
      ),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        'type',
        CloudDriveErrorType.incompatible,
      )),
    );
  });

  test('百度错误码映射为鉴权、权限、未找到和限流', () {
    for (final fixture in <(int, CloudDriveErrorType)>[
      (-6, CloudDriveErrorType.authentication),
      (-7, CloudDriveErrorType.permission),
      (-9, CloudDriveErrorType.notFound),
      (31034, CloudDriveErrorType.rateLimited),
    ]) {
      expect(
        () => parser.parseDirectoryPage(<String, Object?>{
          'errno': fixture.$1,
          'request_id': 900000000,
        }),
        throwsA(isA<CloudDriveException>().having(
          (error) => error.type,
          'type',
          fixture.$2,
        )),
      );
    }
  });

  test('畸形字段不会被当成空目录', () {
    expect(
      () => parser.parseDirectoryPage(<String, Object?>{
        'errno': 0,
        'list': <Object?>[
          <String, Object?>{'fs_id': 'wrong-type'}
        ],
      }),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        'type',
        CloudDriveErrorType.incompatible,
      )),
    );
  });
}

Future<Map<String, Object?>> _fixture(String name) async =>
    Map<String, Object?>.from(
      jsonDecode(
        await File('test/fixtures/baidu/$name').readAsString(),
      ) as Map<Object?, Object?>,
    );
