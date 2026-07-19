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
}
