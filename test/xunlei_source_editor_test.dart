import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_source_editor.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_verification_dialog.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

void main() {
  testWidgets('未配置迅雷构建凭据时禁用授权入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: XunleiSourceEditorPage()),
    );
    await tester.pump();

    expect(find.text('当前构建未配置迅雷授权'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '验证并登录'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>('xunlei-refresh-token'),
              ),
              matching: find.byType(EditableText),
            ),
          )
          .onSubmitted,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('xunlei-compatible-login')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('xunlei-password')),
              matching: find.byType(EditableText),
            ),
          )
          .onSubmitted,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '兼容登录'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('默认显示 Refresh Token 且兼容账号密码登录折叠', (tester) async {
    final authorization = _FakeXunleiAuthorizationController();
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
      ),
    ));

    final tokenField = find.byKey(
      const ValueKey<String>('xunlei-refresh-token'),
    );
    expect(tokenField, findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
                of: tokenField, matching: find.byType(EditableText)),
          )
          .obscureText,
      isTrue,
    );
    expect(find.text('验证并登录'), findsOneWidget);
    expect(
      find.text(
        '网页 Refresh Token 可能绑定原浏览器设备；目录读取失败时请改用下方账号密码登录',
      ),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey<String>('xunlei-identifier')), findsNothing);
    expect(find.text('账号密码兼容登录'), findsOneWidget);
    expect(
      find.text('推荐使用账号密码登录，以当前设备身份读取迅雷目录'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '选择媒体目录'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(tokenField, 'refresh-user-fixture');
    await tester.tap(find.text('验证并登录'));
    await tester.pumpAndSettle();

    expect(authorization.lastRefreshToken, 'refresh-user-fixture');
    expect(find.text('登录成功：138****0000'), findsOneWidget);
    expect(tester.widget<TextFormField>(tokenField).controller?.text, isEmpty);
  });

  testWidgets('迅雷账号登录后清空密码并允许选择目录', (tester) async {
    final authorization = _FakeXunleiAuthorizationController();
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
      ),
    ));

    await tester.tap(find.text('账号密码兼容登录'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      '13800000000',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );
    await tester.tap(find.text('兼容登录'));
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

  testWidgets('需要设备验证时打开应用内窗口并用新密钥自动续登', (tester) async {
    final authorization = _FakeXunleiAuthorizationController(
      challengeOnLogin: true,
    );
    XunleiVerificationChallenge? openedChallenge;
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
        verificationDialogLauncher: (context, challenge) async {
          openedChallenge = challenge;
          return const XunleiVerificationDialogResult.verified('credit-new');
        },
      ),
    ));
    await tester.tap(find.text('账号密码兼容登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      'account-fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );

    await tester.tap(find.text('兼容登录'));
    await tester.pumpAndSettle();

    expect(openedChallenge?.reviewUri.host, 'i.xunlei.com');
    expect(authorization.completeCreditKey, 'credit-new');
    expect(authorization.completeCalls, 1);
    expect(find.text('登录成功'), findsOneWidget);
    expect(find.textContaining('系统浏览器'), findsNothing);
    expect(find.text('完成验证'), findsNothing);
  });

  testWidgets('明确密码错误清空密码保留账号并恢复焦点', (tester) async {
    final authorization = _FakeXunleiAuthorizationController(
      loginErrorType: CloudDriveErrorType.invalidPassword,
    );
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
      ),
    ));
    await tester.tap(find.text('账号密码兼容登录'));
    await tester.pumpAndSettle();
    final account = find.byKey(const ValueKey<String>('xunlei-identifier'));
    final password = find.byKey(const ValueKey<String>('xunlei-password'));
    await tester.enterText(account, 'account-fixture');
    await tester.enterText(password, 'wrong-password');
    await tester.tap(find.text('兼容登录'));
    await tester.pumpAndSettle();

    expect(find.text('迅雷密码错误，请重新输入'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(account).controller?.text,
      'account-fixture',
    );
    expect(tester.widget<TextFormField>(password).controller?.text, isEmpty);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('非密码错误不误报密码错误并保留对应提示', (tester) async {
    const cases = <CloudDriveErrorType, String>{
      CloudDriveErrorType.network: '网络连接失败，请检查网络后重试',
      CloudDriveErrorType.verificationRequired: '迅雷需要完成设备验证',
      CloudDriveErrorType.protocolUpdated: '迅雷登录协议已更新，请改用 Refresh Token',
      CloudDriveErrorType.authentication: '迅雷账号登录失败，请检查账号或重新登录',
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final authorization = _FakeXunleiAuthorizationController(
        loginErrorType: entry.key,
      );
      await tester.pumpWidget(MaterialApp(
        home: XunleiSourceEditorPage(
          authorizationController: authorization,
          credentialStore: MemoryCloudCredentialStore(),
        ),
      ));
      await tester.tap(find.text('账号密码兼容登录'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('xunlei-identifier')),
        'account-fixture',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('xunlei-password')),
        'password-fixture',
      );
      await tester.tap(find.text('兼容登录'));
      await tester.pumpAndSettle();

      expect(find.text('迅雷密码错误，请重新输入'), findsNothing);
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('取消应用内设备验证会清除挑战且不显示登录失败', (tester) async {
    final authorization = _FakeXunleiAuthorizationController(
      challengeOnLogin: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
        verificationDialogLauncher: (context, challenge) async =>
            const XunleiVerificationDialogResult.cancelled(),
      ),
    ));
    await tester.tap(find.text('账号密码兼容登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      'account-fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );
    await tester.tap(find.text('兼容登录'));
    await tester.pumpAndSettle();

    expect(authorization.cancelCalls, 1);
    expect(authorization.completeCalls, 0);
    expect(authorization.verificationChallenge, isNull);
    expect(find.textContaining('登录失败'), findsNothing);
  });

  testWidgets('应用内验证组件失败会清除挑战并显示精确提示', (tester) async {
    const message = '迅雷验证组件不可用，请安装或修复 Microsoft Edge WebView2 Runtime';
    final authorization = _FakeXunleiAuthorizationController(
      challengeOnLogin: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        authorizationController: authorization,
        credentialStore: MemoryCloudCredentialStore(),
        verificationDialogLauncher: (context, challenge) async =>
            const XunleiVerificationDialogResult.failed(message),
      ),
    ));
    await tester.tap(find.text('账号密码兼容登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-identifier')),
      'account-fixture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('xunlei-password')),
      'password-fixture',
    );
    await tester.tap(find.text('兼容登录'));
    await tester.pumpAndSettle();

    expect(authorization.failCalls, 1);
    expect(authorization.completeCalls, 0);
    expect(authorization.verificationChallenge, isNull);
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('Token 授权失败不覆盖已保存的迅雷凭据', (tester) async {
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

    final tokenField = find.byKey(
      const ValueKey<String>('xunlei-refresh-token'),
    );
    expect(tester.widget<TextFormField>(tokenField).controller?.text, isEmpty);
    await tester.enterText(
      tokenField,
      'refresh-invalid',
    );
    await tester.tap(find.text('重新授权'));
    await tester.pumpAndSettle();

    expect(await store.read(source.id), oldCredential);
    expect(find.text('Refresh Token 无效或已过期，请重新填写'), findsOneWidget);
    expect(find.text('登录成功：138****0000'), findsOneWidget);
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

  testWidgets('目录加载失败后保存仍使用浏览期间刷新的迅雷凭据', (tester) async {
    const source = CloudSource(
      id: 'xunlei-rotated-during-browse',
      type: CloudSourceType.xunlei,
      name: '迅雷网盘',
      baseUrl: 'https://pan.xunlei.com',
      rootPaths: <String>['/影视'],
    );
    const originalCredential = CloudCredential(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      deviceId: '0123456789abcdef0123456789abcdef',
      captchaToken: 'captcha-old',
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
    const rotatedCredential = CloudCredential(
      accessToken: 'access-new',
      refreshToken: 'refresh-new',
      deviceId: '0123456789abcdef0123456789abcdef',
      captchaToken: 'captcha-new',
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
    final store = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: store,
    );
    await repository.save(source);
    await store.write(source.id, originalCredential);
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: store,
      clientFactory: (_, temporaryStore, __) => _RotatingFailingBrowseClient(
        sourceId: source.id,
        credentialStore: temporaryStore,
        rotatedCredential: rotatedCredential,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: XunleiSourceEditorPage(
        source: source,
        controller: controller,
        credentialStore: store,
        authorizationController: _FakeXunleiAuthorizationController(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择媒体目录'));
    await tester.pumpAndSettle();
    expect(find.text('选择迅雷媒体目录'), findsOneWidget);
    Navigator.of(tester.element(find.text('选择迅雷媒体目录'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final savedCredential = await store.read(source.id);
    expect(savedCredential?.refreshToken, rotatedCredential.refreshToken);
    expect(savedCredential?.captchaToken, rotatedCredential.captchaToken);
    controller.dispose();
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
      find.byKey(const ValueKey<String>('xunlei-refresh-token')),
      'refresh-fixture',
    );
    await tester.tap(find.text('验证并登录'));
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
    this.loginErrorType,
  });

  final bool challengeOnLogin;
  final bool failLogin;
  final CloudDriveErrorType? loginErrorType;
  CloudCredential? _credential;
  XunleiAuthorizationState _fakeState = XunleiAuthorizationState.idle;
  XunleiVerificationChallenge? _verificationChallenge;
  String? _error;
  String? lastIdentifier;
  String? lastPassword;
  String? lastRefreshToken;
  String? completeCreditKey;
  int completeCalls = 0;
  int cancelCalls = 0;
  int failCalls = 0;

  @override
  CloudCredential? get authorizedCredential => _credential;

  @override
  XunleiAuthorizationState get state => _fakeState;

  @override
  XunleiVerificationChallenge? get verificationChallenge =>
      _verificationChallenge;

  @override
  String? get errorMessage => _error;

  @override
  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    lastIdentifier = identifier;
    lastPassword = password;
    final errorType = loginErrorType;
    if (errorType != null) {
      _fakeState = XunleiAuthorizationState.failed;
      _error = switch (errorType) {
        CloudDriveErrorType.invalidPassword => '迅雷密码错误，请重新输入',
        CloudDriveErrorType.network => '网络连接失败，请检查网络后重试',
        CloudDriveErrorType.verificationRequired => '迅雷需要完成设备验证',
        CloudDriveErrorType.protocolUpdated => '迅雷登录协议已更新，请改用 Refresh Token',
        CloudDriveErrorType.authentication => '迅雷账号登录失败，请检查账号或重新登录',
        _ => '迅雷登录失败',
      };
      notifyListeners();
      throw CloudDriveException(errorType);
    }
    if (failLogin) {
      _fakeState = XunleiAuthorizationState.failed;
      _error = '迅雷登录失败';
      notifyListeners();
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    if (challengeOnLogin) {
      _fakeState = XunleiAuthorizationState.verificationRequired;
      final reviewUri = Uri.parse(
        'https://i.xunlei.com/xlcaptcha/vertifyPhone.html?ticket=fixture',
      );
      _verificationChallenge = XunleiVerificationChallenge(
        reviewUri: reviewUri,
        creditKey: 'credit-initial',
        deviceId: '0123456789abcdef0123456789abcdef',
        deviceSign: 'div101.0123456789abcdef0123456789abcdef-signature-fixture',
        startedAt: DateTime.now().toUtc(),
      );
      notifyListeners();
      throw XunleiVerificationRequired(
        uri: reviewUri,
        creditKey: 'credit-initial',
      );
    }
    _authorize();
  }

  @override
  Future<void> authorizeWithRefreshToken({
    required String refreshToken,
    String? deviceId,
  }) async {
    lastRefreshToken = refreshToken;
    if (failLogin) {
      _fakeState = XunleiAuthorizationState.failed;
      _error = 'Refresh Token 无效或已过期，请重新填写';
      notifyListeners();
      throw const CloudDriveException(CloudDriveErrorType.authentication);
    }
    _authorize();
  }

  @override
  Future<void> completeVerification({required String creditKey}) async {
    completeCalls++;
    completeCreditKey = creditKey;
    _authorize();
  }

  @override
  void cancelVerification() {
    cancelCalls++;
    _verificationChallenge = null;
    _fakeState = XunleiAuthorizationState.idle;
    notifyListeners();
  }

  @override
  void failVerification(String message) {
    failCalls++;
    _verificationChallenge = null;
    _error = message;
    _fakeState = XunleiAuthorizationState.failed;
    notifyListeners();
  }

  void _authorize() {
    _credential = const CloudCredential(
      refreshToken: 'refresh-fixture',
      deviceId: '0123456789abcdef0123456789abcdef',
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
    _verificationChallenge = null;
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
  Future<void> authorizeWithRefreshToken({
    required String refreshToken,
    String? deviceId,
  }) async {
    started.complete();
    await release.future;
    throw const CloudDriveException(CloudDriveErrorType.cancelled);
  }

  @override
  String? get errorMessage => '操作已取消';
}

class _RotatingFailingBrowseClient implements CloudDriveClient {
  const _RotatingFailingBrowseClient({
    required this.sourceId,
    required this.credentialStore,
    required this.rotatedCredential,
  });

  final String sourceId;
  final CloudCredentialStore credentialStore;
  final CloudCredential rotatedCredential;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    await credentialStore.write(sourceId, rotatedCredential);
    throw const CloudDriveException(CloudDriveErrorType.verificationRequired);
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
