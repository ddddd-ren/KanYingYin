import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_response_parser.dart';

void main() {
  const parser = XunleiResponseParser();

  test('解析令牌账号目录分页和原始文件地址', () {
    final session = parser.parseSession(_fixture('refresh_success.json'));
    final account = parser.parseAccount(_fixture('account.json'));
    final page = parser.parseDirectoryPage(_fixture('directory_page_1.json'));
    final detail = parser.parseFileDetail(_fixture('file_detail.json'));

    expect(session.refreshToken, 'refresh-next-fixture');
    expect(session.authorization, 'Bearer access-next-fixture');
    expect(account.userId, 'user-fixture');
    expect(account.accountLabel, '138****0000');
    expect(page.nextPageToken, 'page-2');
    expect(page.files.map((file) => file.id), <String>['folder-a', 'video-a']);
    expect(page.files.first.isDirectory, isTrue);
    expect(page.files.last.size, 1024);
    expect(detail.originalUri.scheme, 'https');
    expect(detail.transcodeUris, hasLength(1));
  });

  test('解析设备验证挑战且异常文本不暴露地址和密钥', () {
    final challenge = parser.parseVerificationRequired(
      _fixture('verification_required.json'),
    );

    expect(challenge.uri.host, 'i.xunlei.com');
    expect(challenge.creditKey, 'credit-fixture');
    expect(challenge.toString(), isNot(contains('credit-fixture')));
    expect(challenge.toString(), isNot(contains('ticket=fixture')));
  });

  test('畸形响应只报告错误类型且不泄露响应内容', () {
    const secret = 'access-token-secret-fixture';

    expect(
      () => parser.parseSession(<String, Object?>{
        'access_token': secret,
      }),
      throwsA(
        isA<CloudDriveException>().having(
          (error) => error.toString(),
          '脱敏错误',
          isNot(contains(secret)),
        ),
      ),
    );
    expect(
      () => parser.parseDirectoryPage(<String, Object?>{
        'files': <Object?>[
          <String, Object?>{
            'kind': 'unknown',
            'id': 'secret-id',
            'name': 'secret-name',
          },
        ],
      }),
      throwsA(isA<CloudDriveException>()),
    );
  });
}

Map<String, Object?> _fixture(String name) => Map<String, Object?>.from(
      jsonDecode(
        File('test/fixtures/xunlei/$name').readAsStringSync(),
      ) as Map,
    );
