import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_verification_dialog.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_bridge.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_profile.dart';

void main() {
  final now = DateTime.utc(2026, 7, 29, 10);

  Future<void> pumpOpenedDialog(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  XunleiVerificationChallenge challenge({DateTime? startedAt}) =>
      XunleiVerificationChallenge(
        reviewUri: Uri.parse(
          'https://i.xunlei.com/xlcaptcha/vertifyPhone.html?ticket=fixture',
        ),
        creditKey: 'credit-initial',
        deviceId: '0123456789abcdef0123456789abcdef',
        deviceSign: 'div101.0123456789abcdef0123456789abcdef-signature-fixture',
        startedAt: startedAt ?? now,
      );

  testWidgets('验证弹窗显示加载状态并允许重试和取消', (tester) async {
    var attempts = 0;
    late XunleiVerificationSurfaceCallbacks callbacks;
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showDialog<XunleiVerificationDialogResult>(
              context: context,
              barrierDismissible: false,
              builder: (_) => XunleiVerificationDialog.test(
                challenge: challenge(),
                now: () => now,
                surfaceBuilder: (value, attempt) {
                  callbacks = value;
                  attempts = attempt;
                  return const ColoredBox(color: Colors.black);
                },
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    expect(find.text('正在加载迅雷验证页面'), findsOneWidget);

    callbacks.onLoadFailed();
    await tester.pumpAndSettle();
    expect(find.text('迅雷验证页面加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await pumpOpenedDialog(tester);
    expect(attempts, 2);
    expect(find.text('正在加载迅雷验证页面'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result?.outcome, XunleiVerificationDialogOutcome.cancelled);
  });

  testWidgets('成功结果自动关闭并只返回新 CreditKey', (tester) async {
    late XunleiVerificationSurfaceCallbacks callbacks;
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showDialog<XunleiVerificationDialogResult>(
              context: context,
              barrierDismissible: false,
              builder: (_) => XunleiVerificationDialog.test(
                challenge: challenge(),
                now: () => now,
                surfaceBuilder: (value, attempt) {
                  callbacks = value;
                  return const SizedBox.expand();
                },
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    callbacks.onResult(
      const XunleiVerificationResult.success('credit-new'),
    );
    await tester.pumpAndSettle();

    expect(result?.outcome, XunleiVerificationDialogOutcome.verified);
    expect(result?.creditKey, 'credit-new');
    expect(result.toString(), isNot(contains('credit-new')));
    expect(find.text('迅雷设备验证'), findsNothing);
  });

  testWidgets('官方取消结果关闭且不显示失败', (tester) async {
    late XunleiVerificationSurfaceCallbacks callbacks;
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showDialog<XunleiVerificationDialogResult>(
              context: context,
              barrierDismissible: false,
              builder: (_) => XunleiVerificationDialog.test(
                challenge: challenge(),
                now: () => now,
                surfaceBuilder: (value, attempt) {
                  callbacks = value;
                  return const SizedBox.expand();
                },
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    callbacks.onResult(const XunleiVerificationResult.cancelled());
    await tester.pumpAndSettle();

    expect(result?.outcome, XunleiVerificationDialogOutcome.cancelled);
    expect(find.textContaining('失败'), findsNothing);
  });

  testWidgets('失败和协议异常显示明确错误后返回失败', (tester) async {
    for (final item in <(XunleiVerificationResult, String)>[
      (
        const XunleiVerificationResult.failed(),
        '迅雷设备验证失败，请重新登录',
      ),
      (
        const XunleiVerificationResult.incompatible(),
        '迅雷设备验证结果不兼容，请重新登录',
      ),
    ]) {
      late XunleiVerificationSurfaceCallbacks callbacks;
      XunleiVerificationDialogResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return FilledButton(
            onPressed: () async {
              result = await showDialog<XunleiVerificationDialogResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => XunleiVerificationDialog.test(
                  challenge: challenge(),
                  now: () => now,
                  surfaceBuilder: (value, attempt) {
                    callbacks = value;
                    return const SizedBox.expand();
                  },
                ),
              );
            },
            child: const Text('打开验证'),
          );
        }),
      ));
      await tester.tap(find.text('打开验证'));
      await pumpOpenedDialog(tester);
      callbacks.onResult(item.$1);
      await tester.pumpAndSettle();
      expect(find.text(item.$2), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result?.outcome, XunleiVerificationDialogOutcome.failed);
      expect(result?.errorMessage, item.$2);
    }
  });

  testWidgets('不安全导航被阻止且不能重试', (tester) async {
    late XunleiVerificationSurfaceCallbacks callbacks;
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showDialog<XunleiVerificationDialogResult>(
              context: context,
              barrierDismissible: false,
              builder: (_) => XunleiVerificationDialog.test(
                challenge: challenge(),
                now: () => now,
                surfaceBuilder: (value, attempt) {
                  callbacks = value;
                  return const SizedBox.expand();
                },
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    callbacks.onSecurityViolation();
    await tester.pumpAndSettle();
    expect(find.text('已阻止不安全的迅雷验证页面'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(result?.outcome, XunleiVerificationDialogOutcome.failed);
  });

  testWidgets('验证十分钟后自动过期并返回失败', (tester) async {
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showDialog<XunleiVerificationDialogResult>(
              context: context,
              barrierDismissible: false,
              builder: (_) => XunleiVerificationDialog.test(
                challenge: challenge(
                  startedAt: now.subtract(const Duration(minutes: 9)),
                ),
                now: () => now,
                surfaceBuilder: (callbacks, attempt) => const SizedBox.expand(),
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(result?.outcome, XunleiVerificationDialogOutcome.failed);
    expect(result?.errorMessage, '迅雷验证已过期，请重新登录');
  });

  testWidgets('WebView2 Runtime 缺失显示安装或修复提示', (tester) async {
    final originalLoggingSettings =
        PlatformInAppWebViewController.debugLoggingSettings;
    PlatformInAppWebViewController.debugLoggingSettings = DebugLoggingSettings(
      enabled: true,
      usePrint: true,
    );
    addTearDown(() {
      PlatformInAppWebViewController.debugLoggingSettings =
          originalLoggingSettings;
    });
    bool? loggingEnabledDuringProfileCreation;
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showXunleiVerificationDialog(
              context,
              challenge(),
              profileFactory: XunleiVerificationProfileFactory(
                availableVersionLoader: () async {
                  loggingEnabledDuringProfileCreation =
                      PlatformInAppWebViewController
                          .debugLoggingSettings.enabled;
                  return null;
                },
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    const message = '迅雷验证组件不可用，请安装或修复 Microsoft Edge WebView2 Runtime';
    expect(find.text(message), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(result?.outcome, XunleiVerificationDialogOutcome.failed);
    expect(result?.errorMessage, message);
    expect(loggingEnabledDuringProfileCreation, isFalse);
    expect(
      PlatformInAppWebViewController.debugLoggingSettings.enabled,
      isTrue,
    );
    expect(
      PlatformInAppWebViewController.debugLoggingSettings.usePrint,
      isTrue,
    );
  });

  testWidgets('WebView2 Runtime 过旧时提示更新且不打开验证页面', (tester) async {
    XunleiVerificationDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            result = await showXunleiVerificationDialog(
              context,
              challenge(),
              profileFactory: XunleiVerificationProfileFactory(
                availableVersionLoader: () async => '92.0.902.48',
              ),
            );
          },
          child: const Text('打开验证'),
        );
      }),
    ));

    await tester.tap(find.text('打开验证'));
    await pumpOpenedDialog(tester);
    const message = '迅雷验证组件版本过低，请更新 Microsoft Edge WebView2 Runtime';
    expect(find.text(message), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(result?.outcome, XunleiVerificationDialogOutcome.failed);
    expect(result?.errorMessage, message);
  });

  test('验证 WebView 关闭插件调试日志并通过原生事件取消下载', () {
    final source = File(
      'lib/pages/cloud/xunlei/xunlei_verification_dialog.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('PlatformInAppWebViewController.debugLoggingSettings'),
    );
    expect(source, contains('DebugLoggingSettings(enabled: false)'));
    expect(source, contains('onDownloadStarting:'));
    expect(source, contains('DownloadStartResponse('));
    expect(source, contains('DownloadStartResponseAction.CANCEL'));
    expect(source, contains('handled: true'));
    expect(source, isNot(contains('Browser.setDownloadBehavior')));
    expect(source, isNot(contains('Page.setDownloadBehavior')));
    expect(source, isNot(contains('onConsoleMessage:')));
  });
}
