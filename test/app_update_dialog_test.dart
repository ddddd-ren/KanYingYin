import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/app_update/application/windows_update_installer.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/features/app_update/presentation/app_update_dialog.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  testWidgets('显示版本、发布时间、更新说明和操作按钮', (tester) async {
    await tester.pumpWidget(
      _app(
        AppUpdateDialog(
          release: _release(),
          installer: _TestInstaller(
            download: (_) async => File('update.exe'),
          ),
          capabilities: AppPlatformCapabilities.windows,
        ),
      ),
    );

    expect(find.text('发现新版本 2.1.168'), findsOneWidget);
    expect(find.text('发布时间：2026-08-23'), findsOneWidget);
    expect(find.text('版本更新说明'), findsOneWidget);
    expect(find.text('稍后提醒'), findsOneWidget);
    expect(find.text('下载并更新'), findsOneWidget);
  });

  testWidgets('下载时显示进度并禁用重复提交', (tester) async {
    final downloadGate = Completer<void>();
    final installer = _TestInstaller(
      download: (onProgress) async {
        onProgress?.call(1024 * 1024, 2 * 1024 * 1024);
        await downloadGate.future;
        return File('update.exe');
      },
    );
    await tester.pumpWidget(
      _app(AppUpdateDialog(
        release: _release(),
        installer: installer,
        capabilities: AppPlatformCapabilities.windows,
      )),
    );

    await tester.tap(find.text('下载并更新'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('1.00 MB / 2.00 MB'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    downloadGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('校验失败时显示错误并允许重试', (tester) async {
    final installer = _TestInstaller(
      download: (_) async {
        throw const UpdatePackageVerificationException('摘要不匹配');
      },
    );
    await tester.pumpWidget(
      _app(AppUpdateDialog(
        release: _release(),
        installer: installer,
        capabilities: AppPlatformCapabilities.windows,
      )),
    );

    await tester.tap(find.text('下载并更新'));
    await tester.pumpAndSettle();

    expect(find.text('安装包校验失败，请重新下载'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

AppRelease _release() => AppRelease(
      version: SemanticVersion.parse('2.1.168'),
      tagName: 'v2.1.168',
      name: '看影音 2.1.168',
      body: '版本更新说明',
      publishedAt: DateTime.utc(2026, 8, 23),
      assets: <AppReleaseAsset>[
        AppReleaseAsset(
          name: '看影音-2.1.168-测试版-安装程序.exe',
          size: 2 * 1024 * 1024,
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          downloadUri: Uri.parse('https://example.invalid/update.exe'),
        ),
      ],
    );

typedef _DownloadHandler = Future<File> Function(
  UpdateDownloadProgress? onProgress,
);

class _TestInstaller extends WindowsUpdateInstaller {
  _TestInstaller({required _DownloadHandler download}) : _download = download;

  final _DownloadHandler _download;

  @override
  Future<File> downloadAndVerify(
    AppReleaseAsset asset, {
    UpdateDownloadProgress? onProgress,
  }) =>
      _download(onProgress);

  @override
  Future<void> launchAndExit(File installer) async {}
}
