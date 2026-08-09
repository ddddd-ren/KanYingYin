import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/platform/android/android_performance_profile.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_service.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_session.dart';
import 'package:path/path.dart' as p;

void main() {
  test('天玑 930 手机仅为夸克启用两MiB和十路自适应档位', () {
    final mt6877 = AppPlatformCapabilities.android.copyWith(
      androidPerformanceProfile: AndroidPerformanceProfile.mt6877,
    );
    final quark = CloudRangeRelayService.tuningFor(
      capabilities: mt6877,
      providerType: CloudSourceType.quark,
    );

    expect(quark.chunkSize, 2 * 1024 * 1024);
    expect(quark.maxChunks, 64);
    expect(quark.chunkSize * quark.maxChunks, 128 * 1024 * 1024);
    expect(quark.maxConcurrentReads, 8);
    expect(quark.maxConcurrentPrefetch, 7);
    expect(quark.prefetchAheadChunks, 14);
    expect(quark.adaptivePolicy?.maxConcurrentReads, 10);
    expect(quark.adaptivePolicy?.maxConcurrentPrefetch, 9);
    expect(quark.adaptivePolicy?.prefetchAheadChunks, 18);

    expect(
      CloudRangeRelayService.tuningFor(
        capabilities: mt6877,
        providerType: CloudSourceType.baidu,
      ),
      same(CloudRangeRelayTuning.androidHighThroughput),
    );
  });

  test('Android 仅为夸克启用八路自适应上限和192MiB缓存', () {
    final quark = CloudRangeRelayService.tuningFor(
      capabilities: AppPlatformCapabilities.android,
      providerType: CloudSourceType.quark,
    );
    final baidu = CloudRangeRelayService.tuningFor(
      capabilities: AppPlatformCapabilities.android,
      providerType: CloudSourceType.baidu,
    );
    final xunlei = CloudRangeRelayService.tuningFor(
      capabilities: AppPlatformCapabilities.android,
      providerType: CloudSourceType.xunlei,
    );

    expect(quark.maxConcurrentReads, 6);
    expect(quark.maxConcurrentPrefetch, 5);
    expect(quark.prefetchAheadChunks, 10);
    expect(quark.chunkSize * quark.maxChunks, 192 * 1024 * 1024);
    expect(quark.adaptivePolicy?.maxConcurrentReads, 8);
    expect(quark.adaptivePolicy?.maxConcurrentPrefetch, 7);
    expect(quark.adaptivePolicy?.prefetchAheadChunks, 14);

    expect(baidu, same(CloudRangeRelayTuning.androidHighThroughput));
    expect(baidu.adaptivePolicy, isNull);
    expect(baidu.chunkSize * baidu.maxChunks, 128 * 1024 * 1024);
    expect(xunlei, same(CloudRangeRelayTuning.android));
  });

  test('Android TV 的夸克和百度都使用保守调优', () {
    final tv = AppPlatformCapabilities.android.copyWith(
      television: true,
      androidSdkInt: 28,
    );

    for (final providerType in <CloudSourceType>[
      CloudSourceType.quark,
      CloudSourceType.baidu,
    ]) {
      expect(
        CloudRangeRelayService.tuningFor(
          capabilities: tv,
          providerType: providerType,
        ),
        same(CloudRangeRelayTuning.androidTv),
      );
    }
  });

  test('Windows 所有提供方继续使用原有参数', () {
    for (final providerType in CloudSourceType.values) {
      expect(
        CloudRangeRelayService.tuningFor(
          capabilities: AppPlatformCapabilities.windows,
          providerType: providerType,
        ),
        same(CloudRangeRelayTuning.windows),
      );
    }
  });

  test('只清理超过 24 小时且名称匹配的公共中转目录', () async {
    final root = await Directory.systemTemp.createTemp('cloud-relay-root-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final oldSession = await _sessionDirectory(
      root,
      'cloud-relay-00000000000000000000000000000000',
      DateTime.utc(2026, 7, 19),
    );
    final recentSession = await _sessionDirectory(
      root,
      'cloud-relay-11111111111111111111111111111111',
      DateTime.utc(2026, 7, 20, 18),
    );
    final unrelated = await _sessionDirectory(
      root,
      'other-cache',
      DateTime.utc(2026, 7, 19),
    );

    await CloudRangeRelayService.cleanupOrphans(
      root,
      now: DateTime.utc(2026, 7, 21),
    );

    expect(await oldSession.exists(), isFalse);
    expect(await recentSession.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });
}

Future<Directory> _sessionDirectory(
  Directory root,
  String name,
  DateTime createdAt,
) async {
  final directory = await Directory(p.join(root.path, name)).create();
  final marker = File(p.join(directory.path, '.created'));
  await marker.writeAsBytes(const <int>[]);
  await marker.setLastModified(createdAt);
  return directory;
}
