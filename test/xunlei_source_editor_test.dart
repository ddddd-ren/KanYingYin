import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_source_editor.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

void main() {
  testWidgets('迅雷账号登录后清空密码并允许选择目录', (tester) async {
    final authorization = _FakeXunleiAuthorizationController();
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
      ),
    ));

    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      '13800000000',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );
    await tester.tap(find.text('登录迅雷'));
    await tester.pumpAndSettle();

    expect(find.text('登录成功'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('xunlei-password')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择媒体目录'),
          )
          .onPressed,
      isNotNull,
    );
    expect(authorization.lastIdentifier, '13800000000');
    expect(authorization.lastPassword, 'password-fixture');
  });

  testWidgets('需要设备验证时用外部浏览器打开并可完成', (tester) async {
    final authorization = _FakeXunleiAuthorizationController(
      challengeOnLogin: true,
    );
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
        launchVerificationUrl: (uri) async {
          opened = uri;
          return true;
        },
      ),
    ));
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      'account-fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );

    await tester.tap(find.text('登录迅雷'));
    await tester.pumpAndSettle();

    expect(opened, Uri.parse('https://i.xunlei.com/verify?id=fixture'));
    expect(find.text('完成验证'), findsOneWidget);
    expect(find.text('取消验证'), findsOneWidget);
    await tester.tap(find.text('完成验证'));
    await tester.pumpAndSettle();
    expect(find.text('登录成功'), findsOneWidget);
    expect(authorization.completeCalls, 1);
  });

  testWidgets('登录失败不覆盖已保存的迅雷凭据', (tester) async {
    const source = CloudSource(
      id: 'xunlei-existing',
      type: CloudSourceType.xunlei,
      name: '迅雷网盘',
      baseUrl: 'https://pan.xunlei.com',
      rootPaths: <String>['/影视'],
    );
    const oldCredential = CloudCredential(
      refreshToken: 'refresh-old',
      deviceId: '0123456789abcdef0123456789abcdef',
      userId: 'user-old',
      accountLabel: '138****0000',
    );
    final store = MemoryCloudCredentialStore();
    await store.write(source.id, oldCredential);
    final authorization = _FakeXunleiAuthorizationController(failLogin: true);
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        source: source,
        authorizationController: authorization,
        credentialStore: store,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('xunlei-password')),
          )
          .controller
          ?.text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      'account-fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'wrong-password',
    );
    await tester.tap(find.text('登录迅雷'));
    await tester.pumpAndSettle();

    expect(await store.read(source.id), oldCredential);
    expect(find.text('迅雷登录失败'), findsOneWidget);
  });

  testWidgets('编辑已授权来源可清除目录并保存回传来源 ID', (tester) async {
    const source = CloudSource(
      id: 'xunlei-save',
      type: CloudSourceType.xunlei,
      name: '迅雷归档',
      baseUrl: 'https://pan.xunlei.com',
      rootPaths: <String>['/影视'],
    );
    const credential = CloudCredential(
      refreshToken: 'refresh-fixture',
      deviceId: '0123456789abcdef0123456789abcdef',
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
    final store = MemoryCloudCredentialStore();
    await store.write(source.id, credential);
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: store,
    );
    await repository.save(source);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: store,
    );
    String? result;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => XunleiSourceEditorPage(
                  source: source,
                  controller: controller,
                  credentialStore: store,
                  authorizationController: _FakeXunleiAuthorizationController(),
                ),
              ),
            );
          },
          child: const Text('打开'),
        );
      }),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final clear = find.byKey(
      const ValueKey<String>('clear-cloud-media-roots'),
    );
    expect(find.text('/影视'), findsOneWidget);
    await tester.tap(clear);
    await tester.pump();
    expect(find.text('尚未选择'), findsOneWidget);
    expect(tester.widget<TextButton>(clear).onPressed, isNull);

    // 恢复原目录后保存，验证路由回传和既有授权复用。
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();

    // 单独验证保存路径，避免目录选择器耦合此交互测试。
    final saveController = CloudLibraryController(
      repository: repository,
      credentialStore: store,
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => XunleiSourceEditorPage(
                  source: source,
                  controller: saveController,
                  credentialStore: store,
                  authorizationController: _FakeXunleiAuthorizationController(),
                ),
              ),
            );
          },
          child: const Text('再次打开'),
        );
      }),
    ));
    await tester.tap(find.text('再次打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, source.id);
    expect((await repository.getById(source.id))?.rootPaths, <String>['/影视']);
    saveController.dispose();
  });

  testWidgets('登录请求未完成时退出页面不访问已销毁输入框', (tester) async {
    final authorization = _BlockingXunleiAuthorizationController();
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
      ),
    ));
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      'account-fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );
    await tester.tap(find.text('登录迅雷'));
    await authorization.started.future;

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    authorization.release.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _FakeXunleiAuthorizationController extends XunleiAuthorizationController {
  _FakeXunleiAuthorizationController({
    this.challengeOnLogin = false,
    this.failLogin = false,
  });

  final bool challengeOnLogin;
  final bool failLogin;
  CloudCredential? _credential;
  XunleiAuthorizationState _fakeState = XunleiAuthorizationState.idle;
  Uri? _verificationUri;
  String? _error;
  String? lastIdentifier;
  String? lastPassword;
  int completeCalls = 0;

  @override
  CloudCredential? get authorizedCredential => _credential;

  @override
  XunleiAuthorizationState get state => _fakeState;

  @override
  Uri? get verificationUri => _verificationUri;

  @override
  String? get errorMessage => _error;

  @override
  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    lastIdentifier = identifier;
    lastPassword = password;
    if (failLogin) {
      _fakeState = XunleiAuthorizationState.failed;
      _error = '迅雷登录失败';
      notifyListeners();
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    if (challengeOnLogin) {
      _fakeState = XunleiAuthorizationState.verificationRequired;
      _verificationUri = Uri.parse('https://i.xunlei.com/verify?id=fixture');
      notifyListeners();
      throw XunleiVerificationRequired(
        uri: _verificationUri!,
        creditKey: 'credit-fixture',
      );
    }
    _authorize();
  }

  @override
  Future<void> completeVerification() async {
    completeCalls++;
    _authorize();
  }

  @override
  void cancelVerification() {
    _verificationUri = null;
    _fakeState = XunleiAuthorizationState.idle;
    notifyListeners();
  }

  void _authorize() {
    _credential = const CloudCredential(
      refreshToken: 'refresh-fixture',
      deviceId: '0123456789abcdef0123456789abcdef',
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
    _verificationUri = null;
    _error = null;
    _fakeState = XunleiAuthorizationState.authorized;
    notifyListeners();
  }
}

class _BlockingXunleiAuthorizationController
    extends XunleiAuthorizationController {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    started.complete();
    await release.future;
    throw const CloudDriveException(CloudDriveErrorType.cancelled);
  }

  @override
  String? get errorMessage => '操作已取消';
}
