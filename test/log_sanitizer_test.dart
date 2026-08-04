import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/log_sanitizer.dart';

void main() {
  const sanitizer = LogSanitizer();

  test('日志脱敏保留本地 Windows 媒体路径', () {
    const input = r'正在打开 D:\影片\测试\第 01 集.mkv';

    expect(sanitizer.sanitize(input), input);
  });

  test('日志脱敏只保留远程 URL 的协议主机和端口', () {
    final result = sanitizer.sanitize(
      'GET https://user:pass@drive.example.com:5244/private/a.mkv'
      '?token=abc#part',
    );

    expect(result, contains('https://drive.example.com:5244'));
    expect(result, isNot(contains('user')));
    expect(result, isNot(contains('pass')));
    expect(result, isNot(contains('/private/a.mkv')));
    expect(result, isNot(contains('token=abc')));
  });

  test('日志脱敏隐藏请求头和常见凭据字段', () {
    final result = sanitizer.sanitize(
      'Authorization: Bearer authorizationValue token=tokenValue '
      'api_key=apiValue signature=signatureValue password=passwordValue '
      'Cookie: cookieValue',
    );

    for (final secret in [
      'authorizationValue',
      'cookieValue',
      'tokenValue',
      'apiValue',
      'signatureValue',
      'passwordValue',
    ]) {
      expect(result, isNot(contains(secret)));
    }
    expect('[REDACTED]'.allMatches(result), hasLength(6));
  });

  test('完整隐藏包含分号和空格的 Cookie 请求头', () {
    const cookie =
        'session=fixture-one; user_name=fixture user; __puus=fixture-three';
    final result =
        sanitizer.sanitize('Cookie: $cookie\nAccept: application/json');

    expect(result, contains('Cookie: [REDACTED]'));
    expect(result, contains('Accept: application/json'));
    expect(result, isNot(contains('fixture-one')));
    expect(result, isNot(contains('fixture user')));
    expect(result, isNot(contains('fixture-three')));
  });

  test('对外脱敏覆盖结构化、查询串和 camelCase 凭据字段', () {
    const input = '''
{"accessToken":"json-access-value","refresh_token":"json-refresh-value","clientSecret":"json-client-value","apiKey":"json-api-value","password":"json-password-value","cookie":"sid=json-cookie-value","authorization":"Bearer json-authorization-value","public":"json-visible"}
{accessToken: map-access-value, refreshToken: map-refresh-value, client_secret: map-client-value, api_key: map-api-value, password: map-password-value, cookie: map-cookie-value, authorization: map-authorization-value, status: map-visible}
accessToken=query-access-value&refresh_token=query-refresh-value&clientSecret=query-client-value&apiKey=query-api-value&password=query-password-value&cookie=query-cookie-value&authorization=query-authorization-value&public=query-visible
''';

    final result = sanitizer.sanitizeForExport(input);

    for (final secret in <String>[
      'json-access-value',
      'json-refresh-value',
      'json-client-value',
      'json-api-value',
      'json-password-value',
      'json-cookie-value',
      'json-authorization-value',
      'map-access-value',
      'map-refresh-value',
      'map-client-value',
      'map-api-value',
      'map-password-value',
      'map-cookie-value',
      'map-authorization-value',
      'query-access-value',
      'query-refresh-value',
      'query-client-value',
      'query-api-value',
      'query-password-value',
      'query-cookie-value',
      'query-authorization-value',
    ]) {
      expect(result, isNot(contains(secret)), reason: secret);
    }
    expect(result, contains('"public":"json-visible"'));
    expect(result, contains('status: map-visible'));
    expect(result, contains('&public=query-visible'));
  });

  test('对外脱敏完整隐藏未加引号且含空格的凭据值', () {
    const input = '''
Authorization: Basic dXNlcjpwYXNz
{password: map-first map-second map-third, status: map-visible, apiKey: map-api-secret}
password=loose-first loose-second nextField=loose-visible
{"password":"json secret words","public":"json-visible"}
password=query-secret&public=query-visible
''';

    final result = sanitizer.sanitizeForExport(input);

    for (final secret in <String>[
      'dXNlcjpwYXNz',
      'map-second',
      'map-third',
      'map-api-secret',
      'loose-second',
      'json secret words',
      'query-secret',
    ]) {
      expect(result, isNot(contains(secret)), reason: secret);
    }
    expect(result, contains('Authorization: [REDACTED]'));
    expect(result, contains('status: map-visible'));
    expect(result, contains('nextField=loose-visible'));
    expect(result, contains('"public":"json-visible"'));
    expect(result, contains('&public=query-visible'));
  });

  test('对外脱敏完整隐藏 Map 中含分号的 Cookie 并保留后续字段', () {
    const input =
        'headers={Cookie: sid=secret-one; user=secret-two, status: ok}';

    final result = sanitizer.sanitizeForExport(input);

    expect(result, 'headers={Cookie: [REDACTED], status: ok}');
  });

  test('对外脱敏完整隐藏 Digest 和 AWS4 Authorization 请求头', () {
    const input = '''
Authorization: Digest username=alice response=digest-secret
Authorization: AWS4-HMAC-SHA256 Credential=aws-credential SignedHeaders=host;x-amz-date Signature=aws-signature
''';

    final result = sanitizer.sanitizeForExport(input);

    expect(
      result,
      'Authorization: [REDACTED]\nAuthorization: [REDACTED]\n',
    );
  });

  test('对外脱敏完整隐藏 Map 中的参数化 Authorization', () {
    const input =
        'headers={Authorization: Digest username=alice, realm=private, '
        'response=map-secret, status: ok}';

    final result = sanitizer.sanitizeForExport(input);

    expect(result, 'headers={Authorization: [REDACTED], status: ok}');
  });

  test('对外脱敏将逗号前缀的 Authorization 识别为 Map 字段', () {
    const input = 'headers=present, Authorization: Digest username=alice, '
        'response=map-secret, status: ok';

    final result = sanitizer.sanitizeForExport(input);

    expect(
      result,
      'headers=present, Authorization: [REDACTED], status: ok',
    );
  });

  test('对外脱敏识别中文普通字段边界', () {
    const input = 'password=secret 状态=登录失败';

    final result = sanitizer.sanitizeForExport(input);

    expect(result, 'password=[REDACTED] 状态=登录失败');
  });

  test('对外脱敏隐藏 Windows、UNC、macOS 和 Linux 本地路径', () {
    const input = r'''
windows="D:\Users\local-user\Private Library\movie.mkv"
unc="\\media-server\local-user\Private Share\movie.mkv"
macos="/Users/local-user/Private Library/movie.mkv"
linux="/home/local-user/private-library/movie.mkv"
''';

    final result = sanitizer.sanitizeForExport(input);

    expect('[LOCAL_PATH]'.allMatches(result), hasLength(4));
    expect(result, isNot(contains('local-user')));
    expect(result.toLowerCase(), isNot(contains('private')));
  });

  test('对外脱敏完整隐藏包含撇号的本地路径', () {
    const input = '''
quoted="/Users/alice/O'Reilly/Private/movie.mkv"
plain=/home/alice/O'Reilly/Private/movie.mkv
''';

    final result = sanitizer.sanitizeForExport(input);

    expect('[LOCAL_PATH]'.allMatches(result), hasLength(2));
    expect(result, isNot(contains('alice')));
    expect(result, isNot(contains("O'Reilly")));
    expect(result, isNot(contains('Private')));
  });
}
