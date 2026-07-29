import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_profile.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Android 迅雷验证不依赖 Windows WebView2 环境', () async {
    final factory = XunleiVerificationProfileFactory(
      capabilities: AppPlatformCapabilities.android,
      availableVersionLoader: () async => throw StateError('不应调用'),
      supportDirectoryLoader: () async => throw StateError('不应调用'),
    );

    final profile = await factory.create();

    expect(profile.environment, isNull);
    await profile.dispose();
  });

  test('WebView2 Runtime 版本必须支持原生下载取消事件', () {
    for (final version in <String>[
      '91.0.864.71',
      '92.0.902.48',
      'invalid-version',
    ]) {
      expect(
        XunleiVerificationProfileFactory.supportsDownloadStarting(version),
        isFalse,
        reason: version,
      );
    }
    for (final version in <String>[
      '92.0.902.49',
      '92.0.902.49 dev',
      '138.0.3351.95',
    ]) {
      expect(
        XunleiVerificationProfileFactory.supportsDownloadStarting(version),
        isTrue,
        reason: version,
      );
    }
  });

  test('过旧 WebView2 Runtime 在创建验证数据目录前被拒绝', () async {
    final support = await Directory.systemTemp.createTemp(
      'xunlei-profile-outdated-',
    );
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final factory = XunleiVerificationProfileFactory(
      availableVersionLoader: () async => '92.0.902.48',
      supportDirectoryLoader: () async => support,
    );

    await expectLater(
      factory.create(),
      throwsA(
        isA<XunleiVerificationProfileException>().having(
          (error) => error.type,
          'type',
          XunleiVerificationProfileError.runtimeOutdated,
        ),
      ),
    );
    expect(
      await Directory(p.join(
        support.path,
        AppIdentity.storageNamespace,
        'webview',
        'xunlei',
      )).exists(),
      isFalse,
    );
  });

  test('WebView2 Runtime 缺失返回脱敏错误且不创建目录', () async {
    final support = await Directory.systemTemp.createTemp(
      'xunlei-profile-missing-',
    );
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final factory = XunleiVerificationProfileFactory(
      availableVersionLoader: () async => null,
      supportDirectoryLoader: () async => support,
    );

    Object? captured;
    try {
      await factory.create();
    } on Object catch (error) {
      captured = error;
    }

    expect(captured, isA<XunleiVerificationProfileException>());
    expect(
      (captured! as XunleiVerificationProfileException).type,
      XunleiVerificationProfileError.runtimeUnavailable,
    );
    expect(captured.toString(), isNot(contains(support.path)));
    expect(
      await Directory(p.join(
        support.path,
        AppIdentity.storageNamespace,
        'webview',
        'xunlei',
      )).exists(),
      isFalse,
    );
  });

  test('环境初始化失败会删除已创建会话且不暴露异常正文', () async {
    final support = await Directory.systemTemp.createTemp(
      'xunlei-profile-init-',
    );
    addTearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });
    final factory = XunleiVerificationProfileFactory(
      availableVersionLoader: () async => '138.0.3351.95',
      supportDirectoryLoader: () async => support,
      environmentLoader: (_) async => throw StateError('secret-runtime-body'),
      sessionIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    Object? captured;
    try {
      await factory.create();
    } on Object catch (error) {
      captured = error;
    }

    final session = Directory(p.join(
      support.path,
      AppIdentity.storageNamespace,
      'webview',
      'xunlei',
      'session-0123456789abcdef0123456789abcdef',
    ));
    expect(captured, isA<XunleiVerificationProfileException>());
    expect(
      (captured! as XunleiVerificationProfileException).type,
      XunleiVerificationProfileError.initializationFailed,
    );
    expect(captured.toString(), isNot(contains('secret-runtime-body')));
    expect(captured.toString(), isNot(contains(support.path)));
    expect(await session.exists(), isFalse);
  });

  test('只删除专用根目录中的直接会话子目录', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'xunlei-profile-root-',
    );
    addTearDown(() async {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });
    final root = Directory(p.join(workspace.path, 'xunlei'));
    final outside = Directory(p.join(workspace.path, 'outside'));
    final nested = Directory(p.join(
      root.path,
      'nested',
      'session-22222222222222222222222222222222',
    ));
    final invalidName = Directory(p.join(root.path, 'session-invalid'));
    final session = Directory(
      p.join(root.path, 'session-0123456789abcdef0123456789abcdef'),
    );
    await outside.create(recursive: true);
    await nested.create(recursive: true);
    await invalidName.create(recursive: true);
    await session.create(recursive: true);

    expect(
      XunleiVerificationProfileFactory.isSafeSessionDirectory(root, session),
      isTrue,
    );
    for (final unsafe in <Directory>[outside, nested, invalidName]) {
      expect(
        XunleiVerificationProfileFactory.isSafeSessionDirectory(root, unsafe),
        isFalse,
      );
      await expectLater(
        XunleiVerificationProfileFactory.deleteSessionDirectory(
          root: root,
          session: unsafe,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await unsafe.exists(), isTrue);
    }

    await XunleiVerificationProfileFactory.deleteSessionDirectory(
      root: root,
      session: session,
    );
    expect(await session.exists(), isFalse);
  });
}
