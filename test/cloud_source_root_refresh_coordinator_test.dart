import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';

void main() {
  test('按双刷新单次扫描双刷新的顺序更新来源', () async {
    final calls = <String>[];
    final coordinator = CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () async => calls.add('local'),
      reloadCloudResources: () async => calls.add('cloud'),
      scanSource: (sourceId) async {
        calls.add('scan:$sourceId');
        return _successfulScan;
      },
    );

    await coordinator.refreshSource('baidu-a');

    expect(calls, <String>[
      'local',
      'cloud',
      'scan:baidu-a',
      'local',
      'cloud',
    ]);
  });

  test('扫描部分失败后仍执行后置重载并统一抛错', () async {
    final calls = <String>[];
    final coordinator = CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () async => calls.add('local'),
      reloadCloudResources: () async => calls.add('cloud'),
      scanSource: (_) async {
        calls.add('scan');
        return const CloudMediaScanResult(
          scanned: 1,
          skipped: 0,
          failures: 1,
          failedPaths: <String>['/B'],
          cancelled: false,
        );
      },
    );

    await expectLater(
      coordinator.refreshSource('source-a'),
      throwsA(
        isA<CloudSourceRootRefreshException>().having(
          (error) => error.cause.toString(),
          '原因',
          contains('网盘媒体扫描未完整完成'),
        ),
      ),
    );
    expect(calls, <String>['local', 'cloud', 'scan', 'local', 'cloud']);
  });

  test('前置刷新失败仍继续扫描和后置刷新并保留首个原因', () async {
    final calls = <String>[];
    final firstError = StateError('本地视图刷新失败');
    var localReloadCount = 0;
    final coordinator = CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () async {
        calls.add('local');
        localReloadCount++;
        if (localReloadCount == 1) throw firstError;
      },
      reloadCloudResources: () async => calls.add('cloud'),
      scanSource: (_) async {
        calls.add('scan');
        return _successfulScan;
      },
    );

    await expectLater(
      coordinator.refreshSource('source-a'),
      throwsA(
        isA<CloudSourceRootRefreshException>().having(
          (error) => error.cause,
          '首个原因',
          same(firstError),
        ),
      ),
    );
    expect(calls, <String>['local', 'cloud', 'scan', 'local', 'cloud']);
  });

  test('扫描取消按更新失败处理且不会跳过后置刷新', () async {
    var cloudReloadCount = 0;
    final coordinator = CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () async {},
      reloadCloudResources: () async => cloudReloadCount++,
      scanSource: (_) async => const CloudMediaScanResult(
        scanned: 0,
        skipped: 0,
        failures: 0,
        failedPaths: <String>[],
        cancelled: true,
      ),
    );

    await expectLater(
      coordinator.refreshSource('source-a'),
      throwsA(isA<CloudSourceRootRefreshException>()),
    );
    expect(cloudReloadCount, 2);
  });
}

const _successfulScan = CloudMediaScanResult(
  scanned: 1,
  skipped: 0,
  failures: 0,
  failedPaths: <String>[],
  cancelled: false,
);
