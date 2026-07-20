import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';

void main() {
  const policy = QuarkRequestPolicy();
  const cookie = 'session=cookie-fixture; __puus=fixture';

  test('Cookie 只发送到夸克 API 和受信任的首始播放主机', () {
    final apiHeaders = policy.headersFor(
      Uri.parse('https://drive.quark.cn/1/clouddrive/file/sort'),
      cookie: cookie,
    );
    final playback = Uri.parse('https://media.quark-fixture.invalid/video');
    final playbackHeaders = policy.headersFor(
      playback,
      cookie: cookie,
      playbackOrigin: playback,
    );
    final untrustedHeaders = policy.headersFor(
      Uri.parse('https://redirect.example.invalid/video'),
      cookie: cookie,
      playbackOrigin: playback,
    );

    expect(apiHeaders['Cookie'], cookie);
    expect(playbackHeaders['Cookie'], cookie);
    expect(untrustedHeaders, isNot(contains('Cookie')));
  });

  test('跨主机重定向剥离 Cookie，同主机重定向保留', () {
    final origin = Uri.parse('https://media.quark-fixture.invalid/video');
    final headers = policy.headersFor(
      origin,
      cookie: cookie,
      playbackOrigin: origin,
    );

    expect(
      policy.headersForRedirect(
        from: origin,
        to: Uri.parse('https://media.quark-fixture.invalid/next'),
        headers: headers,
      )['Cookie'],
      cookie,
    );
    expect(
      policy.headersForRedirect(
        from: origin,
        to: Uri.parse('https://cdn.example.invalid/next'),
        headers: headers,
      ),
      isNot(contains('Cookie')),
    );
  });

  test('原文件请求头只允许夸克 HTTPS 下载主机', () {
    final trusted = policy.originalDownloadHeadersFor(
      Uri.parse('https://download.drive.quark.cn/file'),
      cookie: cookie,
    );
    expect(trusted, <String, String>{
      'Cookie': cookie,
      'Referer': 'https://pan.quark.cn',
      'User-Agent': QuarkRequestPolicy.userAgent,
    });
    for (final uri in <Uri>[
      Uri.parse('http://download.drive.quark.cn/file'),
      Uri.parse('https://evilquark.cn/file'),
      Uri.parse('https://drive.quark.cn.example.com/file'),
    ]) {
      expect(policy.isTrustedOriginalDownloadUri(uri), isFalse);
      expect(
        policy.originalDownloadHeadersFor(uri, cookie: cookie),
        isEmpty,
      );
    }
  });

  test('认证错误不重试，429 和暂时性服务错误有上限重试', () {
    expect(policy.shouldRetry(statusCode: 401, attempt: 0), isFalse);
    expect(policy.shouldRetry(statusCode: 403, attempt: 0), isFalse);
    expect(policy.shouldRetry(statusCode: 429, attempt: 0), isTrue);
    expect(policy.shouldRetry(statusCode: 503, attempt: 1), isTrue);
    expect(policy.shouldRetry(statusCode: 503, attempt: 2), isFalse);
    expect(policy.retryDelay(0), const Duration(milliseconds: 500));
    expect(policy.retryDelay(1), const Duration(seconds: 1));
  });
}
