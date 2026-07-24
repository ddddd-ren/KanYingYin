import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_resources_toolbar.dart';

void main() {
  test('空来源时禁用所有依赖当前来源的操作', () {
    final state = const CloudResourcesToolbarPolicy().evaluate(
      hasSelectedSource: false,
      loading: false,
      scanning: false,
      batchScraping: false,
      autoOrganizing: false,
      tmdbBusy: false,
    );

    expect(state.canChangeSource, isTrue);
    expect(state.canRefresh, isFalse);
    expect(state.canAutoOrganize, isFalse);
    expect(state.canScrape, isFalse);
    expect(state.canRemoveSource, isFalse);
  });

  test('空闲来源开放刷新、整理、刮削和移除', () {
    final state = const CloudResourcesToolbarPolicy().evaluate(
      hasSelectedSource: true,
      loading: false,
      scanning: false,
      batchScraping: false,
      autoOrganizing: false,
      tmdbBusy: false,
    );

    expect(state.canChangeSource, isTrue);
    expect(state.canRefresh, isTrue);
    expect(state.canAutoOrganize, isTrue);
    expect(state.canScrape, isTrue);
    expect(state.canRemoveSource, isTrue);
  });

  test('后台操作按原交互规则精确禁用工具栏动作', () {
    const policy = CloudResourcesToolbarPolicy();

    final tmdbBusy = policy.evaluate(
      hasSelectedSource: true,
      loading: false,
      scanning: false,
      batchScraping: false,
      autoOrganizing: false,
      tmdbBusy: true,
    );
    expect(tmdbBusy.canAutoOrganize, isFalse);
    expect(tmdbBusy.canScrape, isTrue);

    final batch = policy.evaluate(
      hasSelectedSource: true,
      loading: false,
      scanning: false,
      batchScraping: true,
      autoOrganizing: false,
      tmdbBusy: false,
    );
    expect(batch.canAutoOrganize, isFalse);
    expect(batch.canScrape, isFalse);
    expect(batch.canRemoveSource, isTrue);
  });
}
