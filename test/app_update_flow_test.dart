import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/app_update/application/app_update_checker.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/features/app_update/presentation/app_update_flow.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Object?> box;
  late TypedSettings settings;

  setUpAll(() async {
    hiveDirectory = Directory.systemTemp.createTempSync('app-update-flow-');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Object?>('settings');
    settings = TypedSettings(box);
  });

  setUp(() => box.clear());

  tearDownAll(() async {
    await box.close();
    hiveDirectory.deleteSync(recursive: true);
  });

  test('自动检查失败保持静默且不写成功日期', () async {
    final toasts = <String>[];
    final errors = <Object>[];
    final flow = _flow(
      settings: settings,
      fetch: () async => throw StateError('network failed'),
      showToast: toasts.add,
      logError: (error, _) => errors.add(error),
    );

    await flow.runAutomatic();

    expect(toasts, isEmpty);
    expect(errors.single, isA<StateError>());
    expect(_policy(settings).isDue, isTrue);
  });

  test('当天成功检查后自动流程不再请求', () async {
    var requests = 0;
    final policy = _policy(settings);
    await policy.markSuccessful();
    final flow = _flow(
      settings: settings,
      fetch: () async {
        requests++;
        return _release('2.1.168');
      },
    );

    await flow.runAutomatic();

    expect(requests, 0);
  });

  test('自动检查发现更新时展示 Release 并写成功日期', () async {
    final shown = <AppRelease>[];
    final flow = _flow(
      settings: settings,
      fetch: () async => _release('2.1.168'),
      showRelease: (release) async => shown.add(release),
    );

    await flow.runAutomatic();

    expect(shown.single.version.toString(), '2.1.168');
    expect(_policy(settings).isDue, isFalse);
  });

  test('手动检查绕过每日限制并提示当前为测试版', () async {
    await _policy(settings).markSuccessful();
    var requests = 0;
    final toasts = <String>[];
    final flow = _flow(
      settings: settings,
      fetch: () async {
        requests++;
        return _release('1.0.8');
      },
      showToast: toasts.add,
    );

    await flow.runManual();

    expect(requests, 1);
    expect(toasts.single, '当前为高于正式版的测试版本');
  });

  test('手动检查相等版本时提示已是最新版', () async {
    final toasts = <String>[];
    final flow = _flow(
      settings: settings,
      fetch: () async => _release('2.1.167'),
      showToast: toasts.add,
    );

    await flow.runManual();

    expect(toasts.single, '当前已是最新正式版');
  });

  test('Android 平台也执行更新检查', () async {
    var requests = 0;
    final flow = _flow(
      settings: settings,
      capabilities: AppPlatformCapabilities.android,
      fetch: () async {
        requests++;
        return _release('2.1.168');
      },
    );

    await flow.runManual();

    expect(requests, 1);
  });
}

AppUpdateFlow _flow({
  required TypedSettings settings,
  required Future<AppRelease> Function() fetch,
  AppPlatformCapabilities capabilities = AppPlatformCapabilities.windows,
  Future<void> Function(AppRelease)? showRelease,
  void Function(String)? showToast,
  void Function(Object, StackTrace)? logError,
}) =>
    AppUpdateFlow(
      capabilities: capabilities,
      checker: AppUpdateChecker(
        localVersion: SemanticVersion.parse('2.1.167'),
        fetchLatestRelease: fetch,
      ),
      policy: _policy(settings),
      showRelease: showRelease ?? (_) async {},
      showToast: showToast ?? (_) {},
      logError: logError ?? (_, __) {},
    );

DailyUpdateCheckPolicy _policy(TypedSettings settings) =>
    DailyUpdateCheckPolicy(
      settings: settings,
      now: () => DateTime(2026, 8, 23, 12),
    );

AppRelease _release(String version) => AppRelease(
      version: SemanticVersion.parse(version),
      tagName: 'v$version',
      name: '看影音 $version',
      body: '版本更新说明',
      publishedAt: DateTime.utc(2026, 8, 23),
      assets: const <AppReleaseAsset>[],
    );
