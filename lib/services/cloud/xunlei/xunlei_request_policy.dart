import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 迅雷个人云盘目前依赖非公开客户端协议；常量集中在此处便于隔离兼容变化。
class XunleiRequestPolicy {
  const XunleiRequestPolicy();

  static const String clientId = 'Xp6vsxz_7IYVw2BB';
  static const String clientSecret = 'Xp6vsy4tN9toTVdMSpomVdXpRmES';
  static const String clientVersion = '8.31.0.9726';
  static const String packageName = 'com.xunlei.downloadprovider';
  static const String userAgent =
      'ANDROID-com.xunlei.downloadprovider/8.31.0.9726 '
      'netWorkType/5G appid/40 deviceName/Xiaomi_M2004j7ac '
      'deviceModel/M2004J7AC OSVersion/12 protocolVersion/301 '
      'platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 '
      '(Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)';
  static const String downloadUserAgent =
      'Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC '
      'Build/SP1A.210812.016)';
  static const String appId = '40';
  static const String appKey = '34a062aaa22f906fca4fefe9fb3a3021';
  static const List<String> _captchaSalts = <String>[
    '9uJNVj/wLmdwKrJaVj/omlQ',
    'Oz64Lp0GigmChHMf/6TNfxx7O9PyopcczMsnf',
    'Eb+L7Ce+Ej48u',
    'jKY0',
    'ASr0zCl6v8W4aidjPK5KHd1Lq3t+vBFf41dqv5+fnOd',
    'wQlozdg6r1qxh0eRmt3QgNXOvSZO6q/GXK',
    'gmirk+ciAvIgA/cxUUCema47jr/YToixTT+Q6O',
    '5IiCoM9B1/788ntB',
    'P07JH0h6qoM6TSUAK2aL9T5s2QBVeY9JWvalf',
    '+oK0AN',
  ];

  static final Uri coreLoginUri =
      Uri.https('xluser-ssl.xunlei.com', '/xluser.core.login/v3/login');
  static final Uri captchaInitUri =
      Uri.https('xluser-ssl.xunlei.com', '/v1/shield/captcha/init');
  static final Uri signInUri =
      Uri.https('xluser-ssl.xunlei.com', '/v1/auth/signin/token');
  static final Uri refreshUri =
      Uri.https('xluser-ssl.xunlei.com', '/v1/auth/token');
  static final Uri accountUri =
      Uri.https('xluser-ssl.xunlei.com', '/v1/user/me');
  static final Uri filesUri =
      Uri.https('api-pan.xunlei.com', '/drive/v1/files');

  Map<String, String> apiHeaders({required String deviceId}) =>
      <String, String>{
        'accept': 'application/json;charset=UTF-8',
        'user-agent': userAgent,
        'x-device-id': deviceId,
        'x-client-id': clientId,
        'x-client-version': clientVersion,
      };

  String captchaSign({
    required String deviceId,
    required String timestamp,
  }) {
    var value = '$clientId$clientVersion$packageName$deviceId$timestamp';
    for (final salt in _captchaSalts) {
      value = _md5('$value$salt');
    }
    return '1.$value';
  }

  String deviceSign(String deviceId) {
    final sha1Value = sha1.convert(
      utf8.encode('$deviceId$packageName$appId$appKey'),
    );
    return 'div101.$deviceId${_md5(sha1Value.toString())}';
  }

  bool isTrustedVerificationUri(Uri uri) =>
      _isTrustedHttps(uri, const <String>{'i.xunlei.com'});

  bool isTrustedDownloadUri(Uri uri) => _isTrustedHttps(
        uri,
        const <String>{
          'xunlei.com',
          'sandai.net',
        },
        allowSubdomains: true,
      );

  bool _isTrustedHttps(
    Uri uri,
    Set<String> allowedHosts, {
    bool allowSubdomains = false,
  }) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    final host = uri.host.toLowerCase();
    for (final allowed in allowedHosts) {
      if (host == allowed || (allowSubdomains && host.endsWith('.$allowed'))) {
        return true;
      }
    }
    return false;
  }

  String _md5(String value) => md5.convert(utf8.encode(value)).toString();
}
