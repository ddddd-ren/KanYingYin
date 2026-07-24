import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_source_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';

void main() {
  test('同一时间只允许一个网盘来源扫描', () {
    final coordinator = CloudSourceCoordinator();
    final handle = coordinator.beginScan('source-a');

    expect(coordinator.activeSourceId, 'source-a');
    expect(
      () => coordinator.beginScan('source-b'),
      throwsA(isA<CloudScanInProgressException>()),
    );

    handle.complete();
    expect(coordinator.activeSourceId, isNull);
  });

  test('取消扫描会通知令牌并等待当前扫描结束', () async {
    final coordinator = CloudSourceCoordinator();
    final handle = coordinator.beginScan('source-a');

    coordinator.cancel('source-a');
    expect(handle.token.isCancelled, isTrue);

    var completed = false;
    final waiting =
        coordinator.waitFor('source-a').then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    handle.complete();
    await waiting;
    expect(completed, isTrue);
  });
}
