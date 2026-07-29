import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_bridge.dart';

void main() {
  const deviceId = '0123456789abcdef0123456789abcdef';
  final challenge = XunleiVerificationChallenge(
    reviewUri: Uri.parse(
      'https://i.xunlei.com/xlcaptcha/vertifyPhone.html?ticket=fixture',
    ),
    creditKey: 'credit-"\\\n雪-fixture',
    deviceId: deviceId,
    deviceSign: 'div101.$deviceId-signature',
    startedAt: DateTime.utc(2026, 7, 29, 10),
  );

  test('挑战对象和桥接对象字符串不暴露秘密', () {
    final bridge = XunleiVerificationBridge(challenge);

    expect(challenge.toString(), 'XunleiVerificationChallenge(<redacted>)');
    expect(bridge.toString(), 'XunleiVerificationBridge(<redacted>)');
    expect(challenge.toString(), isNot(contains('credit-')));
    expect(bridge.toString(), isNot(contains('ticket=fixture')));
  });

  test('文档开始脚本用 JSON 编码并限制来源消息和回调名', () {
    final script = XunleiVerificationBridge(challenge).documentStartScript;
    final encodedPayload = jsonEncode(<String, String>{
      'creditkey': challenge.creditKey,
      'reviewurl': challenge.reviewUri.toString(),
      'deviceid': challenge.deviceId,
      'devicesign': challenge.deviceSign,
    });

    expect(script, contains(encodedPayload));
    expect(script, contains("location.protocol !== 'https:'"));
    expect(script, contains("location.hostname !== 'i.xunlei.com'"));
    expect(script, contains("callbackName !== 'reviewCb'"));
    expect(script, contains("name === 'nativeGetUserDeviceInfo'"));
    expect(script, contains("name === 'nativeRecvOperationResult'"));
    expect(script, contains("callHandler('xunleiVerificationResult', data)"));
    expect(script, contains('return false;'));
    expect(script, isNot(contains('console.log')));
  });

  test('同时解析字符串和 Map 成功结果', () {
    final bridge = XunleiVerificationBridge(challenge);
    for (final raw in <Object>[
      '{"roErrorCode":"0","roData":{"creditkey":"credit-new"}}',
      <String, Object?>{
        'roErrorCode': '0',
        'roData': <String, Object?>{'creditkey': 'credit-new'},
      },
    ]) {
      final result = bridge.parseOperationResult(raw);
      expect(result.outcome, XunleiVerificationOutcome.success);
      expect(result.creditKey, 'credit-new');
      expect(result.toString(), isNot(contains('credit-new')));
    }
  });

  test('取消失败缺少新密钥超长和畸形消息映射明确', () {
    final bridge = XunleiVerificationBridge(challenge);
    expect(
      bridge.parseOperationResult('{"roErrorCode":"30001"}').outcome,
      XunleiVerificationOutcome.cancelled,
    );
    expect(
      bridge.parseOperationResult('{"roErrorCode":"9"}').outcome,
      XunleiVerificationOutcome.failed,
    );
    expect(
      bridge.parseOperationResult('{"roErrorCode":"0","roData":{}}').outcome,
      XunleiVerificationOutcome.incompatible,
    );
    expect(
      bridge.parseOperationResult(<String, Object?>{
        'roErrorCode': '0',
        'roData': <String, Object?>{'creditkey': challenge.creditKey},
      }).outcome,
      XunleiVerificationOutcome.incompatible,
    );
    expect(
      bridge
          .parseOperationResult(List<String>.filled(16385, 'x').join())
          .outcome,
      XunleiVerificationOutcome.incompatible,
    );
    expect(
      bridge.parseOperationResult(<String, Object?>{
        'roErrorCode': '0',
        'padding': List<String>.filled(16385, 'x').join(),
      }).outcome,
      XunleiVerificationOutcome.incompatible,
    );
    for (final raw in <Object?>[
      '{broken',
      null,
      const <Object?>[],
      <Object?, Object?>{1: 'invalid-key'},
    ]) {
      expect(
        bridge.parseOperationResult(raw).outcome,
        XunleiVerificationOutcome.incompatible,
      );
    }
  });

  test('导航策略只允许迅雷精确 HTTPS 主机和默认 443 端口', () {
    expect(
      xunleiVerificationEntryUri.toString(),
      'https://i.xunlei.com/xlcaptcha/android.html',
    );
    for (final value in <String>[
      'https://i.xunlei.com/xlcaptcha/android.html',
      'https://i.xunlei.com:443/xlcaptcha/vertifyPhone.html',
    ]) {
      expect(
        XunleiVerificationNavigationPolicy.allows(Uri.parse(value)),
        isTrue,
      );
    }
    for (final value in <String>[
      'http://i.xunlei.com/xlcaptcha/android.html',
      'https://i.xunlei.com:444/xlcaptcha/android.html',
      'https://user@i.xunlei.com/xlcaptcha/android.html',
      'https://i.xunlei.com.evil.example/xlcaptcha/android.html',
      'https://evil.example/xlcaptcha/android.html',
      'file:///C:/fixture.html',
      'data:text/html,fixture',
      'javascript:alert(1)',
    ]) {
      expect(
        XunleiVerificationNavigationPolicy.allows(Uri.parse(value)),
        isFalse,
        reason: value,
      );
    }
  });

  test('短信校验只允许官方接口的子框架 POST', () {
    final verificationUri = Uri.parse(
      'https://xluser-ssl.xunlei.com/xluser.core.login/v3/checksms',
    );
    expect(
      XunleiVerificationNavigationPolicy.allowsNavigation(
        verificationUri,
        isForMainFrame: false,
        method: 'POST',
      ),
      isTrue,
    );
    for (final item in <(String, bool, String)>[
      (verificationUri.toString(), true, 'POST'),
      (verificationUri.toString(), false, 'GET'),
      (
        'http://xluser-ssl.xunlei.com/xluser.core.login/v3/checksms',
        false,
        'POST'
      ),
      (
        'https://xluser-ssl.xunlei.com:444/xluser.core.login/v3/checksms',
        false,
        'POST'
      ),
      (
        'https://user@xluser-ssl.xunlei.com/xluser.core.login/v3/checksms',
        false,
        'POST'
      ),
      (
        'https://xluser-ssl.xunlei.com/xluser.core.login/v3/sendsms',
        false,
        'POST'
      ),
      ('https://xluser-ssl.xunlei.com/credit/v1/report', false, 'POST'),
      (
        'https://xluser-ssl.xunlei.com.evil.example/xluser.core.login/v3/checksms',
        false,
        'POST'
      ),
    ]) {
      expect(
        XunleiVerificationNavigationPolicy.allowsNavigation(
          Uri.parse(item.$1),
          isForMainFrame: item.$2,
          method: item.$3,
        ),
        isFalse,
        reason: item.toString(),
      );
    }
  });
}
