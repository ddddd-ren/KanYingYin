import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/app_update/application/app_update_checker.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Object?> box;
  late TypedSettings settings;

  setUpAll(() async {
    hiveDirectory = Directory.systemTemp.createTempSync('app-update-checker-');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Object?>('settings');
    settings = TypedSettings(box);
  });

  setUp(() => box.clear());

  tearDownAll(() async {
    await box.close();
    hiveDirectory.deleteSync(recursive: true);
  });

  test('远端更高时返回可更新版本', () async {
    final checker = AppUpdateChecker(
      localVersion: SemanticVersion.parse('2.1.167'),
      fetchLatestRelease: () async => _release('2.1.168'),
    );

    final result = await checker.check();

    expect(result.status, AppUpdateCheckStatus.updateAvailable);
    expect(result.release?.version.toString(), '2.1.168');
  });

  test('版本相等时返回已是最新版', () async {
    final checker = AppUpdateChecker(
      localVersion: SemanticVersion.parse('2.1.167'),
      fetchLatestRelease: () async => _release('2.1.167'),
    );

    expect((await checker.check()).status, AppUpdateCheckStatus.upToDate);
  });

  test('本地测试版高于正式版时拒绝降级', () async {
    final checker = AppUpdateChecker(
      localVersion: SemanticVersion.parse('2.1.167'),
      fetchLatestRelease: () async => _release('1.0.8'),
    );

    expect((await checker.check()).status, AppUpdateCheckStatus.localAhead);
  });

  test('只有成功标记后才跳过当天检查', () async {
    final policy = DailyUpdateCheckPolicy(
      settings: settings,
      now: () => DateTime(2026, 8, 23, 12),
    );

    expect(policy.isDue, isTrue);
    await policy.markSuccessful();
    expect(policy.isDue, isFalse);
    expect(
      settings.getTyped<String>(
        SettingBoxKey.lastSuccessfulUpdateCheckDate,
        defaultValue: '',
      ),
      '2026-08-23',
    );
  });

  test('错误类型的旧设置值按未检查处理', () async {
    await box.put(SettingBoxKey.lastSuccessfulUpdateCheckDate, 20260823);
    final policy = DailyUpdateCheckPolicy(
      settings: settings,
      now: () => DateTime(2026, 8, 23),
    );

    expect(policy.isDue, isTrue);
  });
}

AppRelease _release(String version) => AppRelease(
      version: SemanticVersion.parse(version),
      tagName: 'v$version',
      name: '看影音 $version',
      body: '更新说明',
      publishedAt: DateTime.utc(2026, 8, 23),
      assets: const <AppReleaseAsset>[],
    );
