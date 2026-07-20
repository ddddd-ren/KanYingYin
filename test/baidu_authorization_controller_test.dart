import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_oauth_client.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';

void main() {
  test('授权地址绑定当前会话的随机 state', () {
    final gateway = _FakeOAuthGateway();
    final controller = BaiduAuthorizationController(
      oauthFactory: ({required clientId, required clientSecret}) => gateway,
      accountLoader: (_) async => _account,
      stateGenerator: () => 'state-fixture',
    );

    final uri = controller.begin(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
    );

    expect(uri.queryParameters['state'], 'state-fixture');
    expect(controller.authorizationUri, uri);
    expect(controller.authorizedCredential, isNull);
  });

  test('授权会话十分钟后拒绝粘贴的授权码', () async {
    final clock = _FakeClock(DateTime.utc(2026, 7, 21, 10));
    final gateway = _FakeOAuthGateway();
    final controller = BaiduAuthorizationController(
      oauthFactory: ({required clientId, required clientSecret}) => gateway,
      accountLoader: (_) async => _account,
      now: clock.call,
      stateGenerator: () => 'state-fixture',
    );

    controller.begin(clientId: 'id', clientSecret: 'secret');
    clock.advance(const Duration(minutes: 11));

    await expectLater(
      controller.exchangeCode('fixture-code'),
      throwsA(
        isA<CloudDriveException>().having(
          (error) => error.type,
          'type',
          CloudDriveErrorType.authentication,
        ),
      ),
    );
    expect(gateway.exchangeCalls, 0);
    expect(controller.errorMessage, '授权会话已过期，请重新打开百度授权');
  });

  test('授权码交换后验证账号并生成完整凭据', () async {
    final gateway = _FakeOAuthGateway();
    String? verifiedAccessToken;
    final controller = BaiduAuthorizationController(
      oauthFactory: ({required clientId, required clientSecret}) => gateway,
      accountLoader: (accessToken) async {
        verifiedAccessToken = accessToken;
        return _account;
      },
      stateGenerator: () => 'state-fixture',
    );

    controller.begin(
        clientId: 'client-fixture', clientSecret: 'secret-fixture');
    await controller.exchangeCode('code-fixture');

    expect(verifiedAccessToken, 'access-fixture');
    expect(controller.account, same(_account));
    expect(controller.authorizedCredential?.clientId, 'client-fixture');
    expect(controller.authorizedCredential?.clientSecret, 'secret-fixture');
    expect(controller.authorizedCredential?.accessToken, 'access-fixture');
    expect(controller.authorizedCredential?.refreshToken, 'refresh-fixture');
    expect(controller.authorizedCredential?.accessTokenExpiresAt, _expiresAt);
    expect(controller.errorMessage, isNull);
  });

  test('同一授权会话的授权码只能提交一次', () async {
    final gateway = _FakeOAuthGateway();
    final controller = BaiduAuthorizationController(
      oauthFactory: ({required clientId, required clientSecret}) => gateway,
      accountLoader: (_) async => _account,
      stateGenerator: () => 'state-fixture',
    );

    controller.begin(clientId: 'id', clientSecret: 'secret');
    await controller.exchangeCode('fixture-code');

    await expectLater(
      controller.exchangeCode('fixture-code'),
      throwsA(isA<CloudDriveException>()),
    );
    expect(gateway.exchangeCalls, 1);
  });
}

final DateTime _expiresAt = DateTime.utc(2026, 8, 21);
const BaiduAccount _account = BaiduAccount(
  displayName: '百度测试账号',
  userId: '10001',
  vipType: 0,
);

class _FakeClock {
  _FakeClock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) => value = value.add(duration);
}

class _FakeOAuthGateway implements BaiduOAuthGateway {
  int exchangeCalls = 0;

  @override
  Uri buildAuthorizationUri({required String state}) => Uri.https(
        'openapi.baidu.com',
        '/oauth/2.0/authorize',
        <String, String>{'state': state},
      );

  @override
  Future<BaiduOAuthTokens> exchangeCode(String code) async {
    exchangeCalls++;
    return BaiduOAuthTokens(
      accessToken: 'access-fixture',
      refreshToken: 'refresh-fixture',
      expiresAt: _expiresAt,
      scopes: <String>{'basic', 'netdisk'},
    );
  }

  @override
  Future<BaiduOAuthTokens> refresh(String refreshToken) =>
      throw UnimplementedError();
}
